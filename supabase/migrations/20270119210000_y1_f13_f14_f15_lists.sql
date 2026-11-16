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

SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_booking (
  booking uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_booking"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_calendar (
  calendar_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_calendar"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_calendar_event (
  event_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_calendar_event"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_field_definition (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_field_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_observation (
  observation_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_observation"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_observation_definition (
  definition_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_observation_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_time_entry"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_trash (
  item_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_trash"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_advisories (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_advisories"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_bookings (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_bookings"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_calendar_events (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_calendar_events"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_calendars (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_calendars"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_care_plans (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_care_plans"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_field_definitions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_field_definitions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_observation_definitions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_observation_definitions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_observations (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_observations"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_time_entries (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_time_entries"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_trash (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_trash"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_vulnerabilities (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_vulnerabilities"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_booking (
  booking uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") from "better_supabase"."bookings" bk where bk."id" = get_booking.booking
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_calendar (
  calendar_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") from "better_supabase"."calendars" k where k."id" = get_calendar.calendar_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_calendar_event (
  event_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) from "better_supabase"."calendar_events" e where e."id" = get_calendar_event.event_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_field_definition (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."field_definitions"%rowtype;
begin
  select * into v_row from "better_supabase"."field_definitions" d where d."id" = get_field_definition.id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'custom_fields.read'), false)) then
    raise exception 'not allowed to read custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'entity', v_row."entity",
    'key', v_row."key",
    'label', v_row."label",
    'type', v_row."type",
    'required', v_row."required",
    'sensitive', v_row."sensitive",
    'encrypted', v_row."encrypted",
    'pack', v_row."pack",
    'packVersion', v_row."pack_version",
    'archivedAt', v_row."archived_at",
    'rank', v_row."rank"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_observation (
  observation_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at")
  from "better_supabase"."observations" x
  join "better_supabase"."observation_definitions" y on y."id" = x."definition_id"
  where x."id" = get_observation.observation_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_observation_definition (
  definition_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."observation_definitions" x where x."id" = get_observation_definition.definition_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_time_entry (
  entry_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."time_entries"%rowtype;
begin
  select * into v_row from "better_supabase"."time_entries" x where x."id" = get_time_entry.entry_id;
  if not found then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_entries.read'), false)) then
    raise exception 'not allowed to read this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_trash (
  item_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row jsonb;
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."trash_items" x where x."id" = get_trash.item_id and x."depth" = 0;
  if v_tenant is null then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'trash.read'), false)) then
    raise exception 'not allowed to read this organization''s trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  select jsonb_build_object('id', t."id", 'subjectType', t."subject_type", 'subjectId', t."subject_id", 'title', t."title", 'batchId', t."batch_id", 'count', t.n, 'trashedBy', t."trashed_by", 'trashedAt', t."trashed_at", 'purgeAfter', t."purge_at")
    into v_row
  from (
    select x.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = x."batch_id")::integer as n
    from "better_supabase"."trash_items" x
    where x."id" = get_trash.item_id
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
  ) t;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_advisories (
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
  v_filters jsonb := coalesce(page_advisories.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_advisories.tenant is not null and coalesce(better_supabase.can('tenant', page_advisories.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'severity') then
      raise exception 'facet is one of status, severity' using errcode = '22023', hint = 'ADVISORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (y."status"::text)::text when 'severity' then (coalesce(y."severity"::text, 'none'))::text end) as v
      from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
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
      select 1 from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'trackingId', 'title') then
    raise exception 'sort is one of createdAt, trackingId, title' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."created_at")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."created_at" >= (v_after ->> 0)::timestamptz and ((y."created_at" > (v_after ->> 0)::timestamptz) or (y."created_at" = (v_after ->> 0)::timestamptz and y."id" < (v_after ->> 1)::uuid))))
      order by y."created_at" asc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."created_at")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."created_at", y."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by y."created_at" desc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."created_at")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."created_at" >= (v_after ->> 0)::timestamptz and ((y."created_at" > (v_after ->> 0)::timestamptz) or (y."created_at" = (v_after ->> 0)::timestamptz and y."id" < (v_after ->> 1)::uuid))))
      order by y."created_at" asc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."created_at")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."created_at", y."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by y."created_at" desc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'trackingId' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."tracking_id")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."tracking_id" >= (v_after ->> 0)::text and ((y."tracking_id" > (v_after ->> 0)::text) or (y."tracking_id" = (v_after ->> 0)::text and y."id" < (v_after ->> 1)::uuid))))
      order by y."tracking_id" asc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'trackingId' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."tracking_id")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."tracking_id", y."id") < ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by y."tracking_id" desc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((lower(y."title"))::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (lower(y."title") >= (v_after ->> 0)::text and ((lower(y."title") > (v_after ->> 0)::text) or (lower(y."title") = (v_after ->> 0)::text and y."id" < (v_after ->> 1)::uuid))))
      order by lower(y."title") asc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'trackingId', y."tracking_id", 'title', y."title", 'summary', y."summary", 'productId', y."product_id", 'severity', y."severity", 'status', y."status", 'revision', y."revision", 'initialReleaseAt', y."initial_release_at", 'currentReleaseAt', y."current_release_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((lower(y."title"))::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (lower(y."title"), y."id") < ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(y."title") desc, y."id" desc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."advisories" y
      where y."tenant_id" = page_advisories.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or y."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or y."severity"::text = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not (v_filters -> 'productId' is not null and jsonb_typeof(v_filters -> 'productId') <> 'null' and not (jsonb_typeof(v_filters -> 'productId') = 'array' and jsonb_array_length(v_filters -> 'productId') = 0)) or y."product_id" = any((case when jsonb_typeof(v_filters -> 'productId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'productId')) else array[v_filters ->> 'productId'] end)::uuid[]))
        and (v_search is null or y."title" ilike v_search or y."tracking_id" ilike v_search or y."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_bookings (
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
  v_filters jsonb := coalesce(page_bookings.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'resourceId') then
      raise exception 'facet is one of status, resourceId' using errcode = '22023', hint = 'BOOKING_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (bk."status"::text)::text when 'resourceId' then (bk."resource_id"::text)::text end) as v
      from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
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
      select 1 from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'createdAt', 'customerName') then
    raise exception 'sort is one of startsAt, createdAt, customerName' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during") >= (v_after ->> 0)::timestamptz and ((lower(bk."during") > (v_after ->> 0)::timestamptz) or (lower(bk."during") = (v_after ->> 0)::timestamptz and bk."id" < (v_after ->> 1)::uuid))))
      order by lower(bk."during") asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during"), bk."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by lower(bk."during") desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during") >= (v_after ->> 0)::timestamptz and ((lower(bk."during") > (v_after ->> 0)::timestamptz) or (lower(bk."during") = (v_after ->> 0)::timestamptz and bk."id" < (v_after ->> 1)::uuid))))
      order by lower(bk."during") asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(bk."during"))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(bk."during"), bk."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by lower(bk."during") desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((bk."created_at")::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (bk."created_at" >= (v_after ->> 0)::timestamptz and ((bk."created_at" > (v_after ->> 0)::timestamptz) or (bk."created_at" = (v_after ->> 0)::timestamptz and bk."id" < (v_after ->> 1)::uuid))))
      order by bk."created_at" asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((bk."created_at")::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (bk."created_at", bk."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by bk."created_at" desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'customerName' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(coalesce(bk."customer_name", '')))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(coalesce(bk."customer_name", '')) >= (v_after ->> 0)::text and ((lower(coalesce(bk."customer_name", '')) > (v_after ->> 0)::text) or (lower(coalesce(bk."customer_name", '')) = (v_after ->> 0)::text and bk."id" < (v_after ->> 1)::uuid))))
      order by lower(coalesce(bk."customer_name", '')) asc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  elsif v_sort = 'customerName' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'BOOKING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', bk."id", 'resourceId', bk."resource_id", 'serviceId', bk."service_id", 'seat', bk."seat", 'startsAt', lower(bk."during"), 'endsAt', upper(bk."during"), 'status', bk."status", 'holdExpiresAt', bk."hold_expires_at", 'customerName', bk."customer_name", 'customerEmail', bk."customer_email", 'customerUserId', bk."customer_id", 'notes', bk."notes", 'seriesId', bk."series_id", 'createdAt', bk."created_at", 'cancelledAt', bk."cancelled_at", 'cancelReason', bk."cancel_reason", 'archivedAt', bk."archived_at") as j, jsonb_build_array((lower(coalesce(bk."customer_name", '')))::text, (bk."id")::text) as k
    from (
      select * from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
        and (v_after is null or (lower(coalesce(bk."customer_name", '')), bk."id") < ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(coalesce(bk."customer_name", '')) desc, bk."id" desc
      limit v_limit + 1 offset v_offset
    ) bk
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."bookings" bk
      where bk."tenant_id" = page_bookings.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or bk."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'resourceId' is not null and jsonb_typeof(v_filters -> 'resourceId') <> 'null' and not (jsonb_typeof(v_filters -> 'resourceId') = 'array' and jsonb_array_length(v_filters -> 'resourceId') = 0)) or bk."resource_id" = any((case when jsonb_typeof(v_filters -> 'resourceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'resourceId')) else array[v_filters ->> 'resourceId'] end)::uuid[]))
        and (not (v_filters -> 'serviceId' is not null and jsonb_typeof(v_filters -> 'serviceId') <> 'null' and not (jsonb_typeof(v_filters -> 'serviceId') = 'array' and jsonb_array_length(v_filters -> 'serviceId') = 0)) or bk."service_id" = any((case when jsonb_typeof(v_filters -> 'serviceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'serviceId')) else array[v_filters ->> 'serviceId'] end)::uuid[]))
        and (not (v_filters -> 'customerId' is not null and jsonb_typeof(v_filters -> 'customerId') <> 'null' and not (jsonb_typeof(v_filters -> 'customerId') = 'array' and jsonb_array_length(v_filters -> 'customerId') = 0)) or bk."customer_id"::text = any((case when jsonb_typeof(v_filters -> 'customerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'customerId')) else array[v_filters ->> 'customerId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or upper(bk."during") > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or lower(bk."during") < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or bk."archived_at" is null)
        and (v_search is null or bk."customer_name" ilike v_search or bk."customer_email" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_calendar_events (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_calendar_events.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'calendarId') then
      raise exception 'facet is one of status, calendarId' using errcode = '22023', hint = 'CALENDAR_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (e."status")::text when 'calendarId' then (e."calendar_id"::text)::text end) as v
      from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
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
      select 1 from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsAt', 'title', 'updatedAt') then
    raise exception 'sort is one of startsAt, title, updatedAt' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((e."starts_at")::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (e."starts_at", e."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by e."starts_at" asc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((e."starts_at")::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (e."starts_at" <= (v_after ->> 0)::timestamptz and ((e."starts_at" < (v_after ->> 0)::timestamptz) or (e."starts_at" = (v_after ->> 0)::timestamptz and e."id" > (v_after ->> 1)::uuid))))
      order by e."starts_at" desc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((e."starts_at")::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (e."starts_at", e."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by e."starts_at" asc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  elsif v_sort = 'startsAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((e."starts_at")::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (e."starts_at" <= (v_after ->> 0)::timestamptz and ((e."starts_at" < (v_after ->> 0)::timestamptz) or (e."starts_at" = (v_after ->> 0)::timestamptz and e."id" > (v_after ->> 1)::uuid))))
      order by e."starts_at" desc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((lower(e."title"))::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (lower(e."title"), e."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(e."title") asc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((lower(e."title"))::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (lower(e."title") <= (v_after ->> 0)::text and ((lower(e."title") < (v_after ->> 0)::text) or (lower(e."title") = (v_after ->> 0)::text and e."id" > (v_after ->> 1)::uuid))))
      order by lower(e."title") desc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((e."updated_at")::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (e."updated_at", e."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by e."updated_at" asc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', e."id", 'calendarId', e."calendar_id", 'uid', e."uid", 'title', e."title", 'startsAt', e."starts_at", 'endsAt', e."ends_at", 'allDay', e."all_day", 'tz', e."tz", 'status', e."status", 'rrule', e."rrule", 'exdates', to_jsonb(e."exdates"), 'recurrenceId', e."recurrence_id", 'originalStart', e."original_starts_at", 'description', e."description", 'location', e."location", 'color', e."color", 'subjectType', e."subject_type", 'subjectId', e."subject_id") || jsonb_build_object('updatedAt', e."updated_at", 'kind', e."kind", 'transparency', e."transparency", 'autoDecline', e."auto_decline", 'attendees', coalesce((select jsonb_agg(jsonb_build_object('email', a."email", 'name', a."name", 'userId', a."user_id", 'role', a."role", 'response', a."response") order by a."email") from "better_supabase"."calendar_attendees" a where a."event_id" = e."id"), '[]'::jsonb), 'alarms', coalesce((select jsonb_agg(jsonb_build_object('id', l."id", 'method', l."method", 'offsetMinutes', l."offset_minutes", 'related', l."related_to", 'at', l."trigger_at", 'repeat', l."repeat_count", 'repeatMinutes', l."repeat_minutes", 'description', l."description", 'summary', l."summary") order by l."offset_minutes" nulls last, l."trigger_at", l."id") from "better_supabase"."calendar_event_alarms" l where l."event_id" = e."id" and (l."user_id" is null or l."user_id" = (select auth.uid()))), '[]'::jsonb)) as j, jsonb_build_array((e."updated_at")::text, (e."id")::text) as k
    from (
      select * from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
        and (v_after is null or (e."updated_at" <= (v_after ->> 0)::timestamptz and ((e."updated_at" < (v_after ->> 0)::timestamptz) or (e."updated_at" = (v_after ->> 0)::timestamptz and e."id" > (v_after ->> 1)::uuid))))
      order by e."updated_at" desc, e."id" asc
      limit v_limit + 1 offset v_offset
    ) e
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."calendar_events" e
      where (not (v_filters -> 'calendarId' is not null and jsonb_typeof(v_filters -> 'calendarId') <> 'null' and not (jsonb_typeof(v_filters -> 'calendarId') = 'array' and jsonb_array_length(v_filters -> 'calendarId') = 0)) or e."calendar_id" = any((case when jsonb_typeof(v_filters -> 'calendarId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'calendarId')) else array[v_filters ->> 'calendarId'] end)::uuid[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or e."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or e."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or e."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or e."ends_at" > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or e."starts_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (v_search is null or e."title" ilike v_search or e."location" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_calendars (
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
  v_filters jsonb := coalesce(page_calendars.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('ownerType') then
      raise exception 'facet is one of ownerType' using errcode = '22023', hint = 'CALENDAR_INVALID';
    end if;
    with s as (
      select (case v_facet when 'ownerType' then (k."owner_type")::text end) as v
      from "better_supabase"."calendars" k
      where k."tenant_id" = page_calendars.tenant
        and (not (v_filters -> 'ownerType' is not null and jsonb_typeof(v_filters -> 'ownerType') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerType') = 'array' and jsonb_array_length(v_filters -> 'ownerType') = 0)) or k."owner_type" = any((case when jsonb_typeof(v_filters -> 'ownerType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerType')) else array[v_filters ->> 'ownerType'] end)::text[]))
        and (v_search is null or k."name" ilike v_search)
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
      select 1 from "better_supabase"."calendars" k
      where k."tenant_id" = page_calendars.tenant
        and (not (v_filters -> 'ownerType' is not null and jsonb_typeof(v_filters -> 'ownerType') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerType') = 'array' and jsonb_array_length(v_filters -> 'ownerType') = 0)) or k."owner_type" = any((case when jsonb_typeof(v_filters -> 'ownerType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerType')) else array[v_filters ->> 'ownerType'] end)::text[]))
        and (v_search is null or k."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name') then
    raise exception 'sort is one of name' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") as j, jsonb_build_array((lower(k."name"))::text, (k."id")::text) as k
    from (
      select * from "better_supabase"."calendars" k
      where k."tenant_id" = page_calendars.tenant
        and (not (v_filters -> 'ownerType' is not null and jsonb_typeof(v_filters -> 'ownerType') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerType') = 'array' and jsonb_array_length(v_filters -> 'ownerType') = 0)) or k."owner_type" = any((case when jsonb_typeof(v_filters -> 'ownerType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerType')) else array[v_filters ->> 'ownerType'] end)::text[]))
        and (v_search is null or k."name" ilike v_search)
        and (v_after is null or (lower(k."name"), k."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(k."name") asc, k."id" asc
      limit v_limit + 1 offset v_offset
    ) k
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") as j, jsonb_build_array((lower(k."name"))::text, (k."id")::text) as k
    from (
      select * from "better_supabase"."calendars" k
      where k."tenant_id" = page_calendars.tenant
        and (not (v_filters -> 'ownerType' is not null and jsonb_typeof(v_filters -> 'ownerType') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerType') = 'array' and jsonb_array_length(v_filters -> 'ownerType') = 0)) or k."owner_type" = any((case when jsonb_typeof(v_filters -> 'ownerType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerType')) else array[v_filters ->> 'ownerType'] end)::text[]))
        and (v_search is null or k."name" ilike v_search)
        and (v_after is null or (lower(k."name") <= (v_after ->> 0)::text and ((lower(k."name") < (v_after ->> 0)::text) or (lower(k."name") = (v_after ->> 0)::text and k."id" > (v_after ->> 1)::uuid))))
      order by lower(k."name") desc, k."id" asc
      limit v_limit + 1 offset v_offset
    ) k
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") as j, jsonb_build_array((lower(k."name"))::text, (k."id")::text) as k
    from (
      select * from "better_supabase"."calendars" k
      where k."tenant_id" = page_calendars.tenant
        and (not (v_filters -> 'ownerType' is not null and jsonb_typeof(v_filters -> 'ownerType') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerType') = 'array' and jsonb_array_length(v_filters -> 'ownerType') = 0)) or k."owner_type" = any((case when jsonb_typeof(v_filters -> 'ownerType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerType')) else array[v_filters ->> 'ownerType'] end)::text[]))
        and (v_search is null or k."name" ilike v_search)
        and (v_after is null or (lower(k."name"), k."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(k."name") asc, k."id" asc
      limit v_limit + 1 offset v_offset
    ) k
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CALENDAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', k."id", 'name', k."name", 'tz', k."tz", 'color', k."color", 'ownerType', k."owner_type", 'ownerId', k."owner_id") as j, jsonb_build_array((lower(k."name"))::text, (k."id")::text) as k
    from (
      select * from "better_supabase"."calendars" k
      where k."tenant_id" = page_calendars.tenant
        and (not (v_filters -> 'ownerType' is not null and jsonb_typeof(v_filters -> 'ownerType') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerType') = 'array' and jsonb_array_length(v_filters -> 'ownerType') = 0)) or k."owner_type" = any((case when jsonb_typeof(v_filters -> 'ownerType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerType')) else array[v_filters ->> 'ownerType'] end)::text[]))
        and (v_search is null or k."name" ilike v_search)
        and (v_after is null or (lower(k."name") <= (v_after ->> 0)::text and ((lower(k."name") < (v_after ->> 0)::text) or (lower(k."name") = (v_after ->> 0)::text and k."id" > (v_after ->> 1)::uuid))))
      order by lower(k."name") desc, k."id" asc
      limit v_limit + 1 offset v_offset
    ) k
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."calendars" k
      where k."tenant_id" = page_calendars.tenant
        and (not (v_filters -> 'ownerType' is not null and jsonb_typeof(v_filters -> 'ownerType') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerType') = 'array' and jsonb_array_length(v_filters -> 'ownerType') = 0)) or k."owner_type" = any((case when jsonb_typeof(v_filters -> 'ownerType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerType')) else array[v_filters ->> 'ownerType'] end)::text[]))
        and (v_search is null or k."name" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_care_plans (
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
  v_filters jsonb := coalesce(page_care_plans.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text end) as v
      from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
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
      select 1 from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'title', 'version', 'startsOn', 'reviewOn') then
    raise exception 'sort is one of createdAt, title, version, startsOn, reviewOn' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title") >= (v_after ->> 0)::text and ((lower(x."title") > (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."id" < (v_after ->> 1)::uuid))))
      order by lower(x."title") asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (lower(x."title"), x."id") < ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."title") desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."version" >= (v_after ->> 0)::integer and ((x."version" > (v_after ->> 0)::integer) or (x."version" = (v_after ->> 0)::integer and x."id" < (v_after ->> 1)::uuid))))
      order by x."version" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'version' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."version")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."version", x."id") < ((v_after ->> 0)::integer, (v_after ->> 1)::uuid))
      order by x."version" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."starts_on"::timestamptz, 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'reviewOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'reviewOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CARE_PLAN_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'status', x."status", 'version', x."version", 'startsOn', x."starts_on", 'reviewOn', x."review_on", 'ownerId', x."owner_id", 'signatureRequestId', x."signature_id", 'agreedAt', x."agreed_at", 'publishedVersionId', x."published_version_id", 'publishedAt', x."published_at", 'publishedBy', x."published_by", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."review_on"::timestamptz, 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."care_plans" x
      where ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false))) and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."status" <> 'archived')
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_field_definitions (
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
  v_filters jsonb := coalesce(page_field_definitions.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_field_definitions.tenant, 'custom_fields.read'), false)) then
    raise exception 'not allowed to read custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('entity', 'type') then
      raise exception 'facet is one of entity, type' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
    end if;
    with s as (
      select (case v_facet when 'entity' then (d."entity")::text when 'type' then (d."type"::text)::text end) as v
      from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
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
      select 1 from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('key', 'label', 'type', 'rank') then
    raise exception 'sort is one of key, label, type, rank' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 4) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."entity")::text, (d."rank" collate "C")::text, (d."key")::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."entity", d."rank" collate "C", d."key", d."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::text, (v_after ->> 3)::uuid))
      order by d."entity" asc, d."rank" collate "C" asc, d."key" asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 4) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."entity")::text, (d."rank" collate "C")::text, (d."key")::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."entity" <= (v_after ->> 0)::text and ((d."entity" < (v_after ->> 0)::text) or (d."entity" = (v_after ->> 0)::text and d."rank" collate "C" > (v_after ->> 1)::text) or (d."entity" = (v_after ->> 0)::text and d."rank" collate "C" = (v_after ->> 1)::text and d."key" > (v_after ->> 2)::text) or (d."entity" = (v_after ->> 0)::text and d."rank" collate "C" = (v_after ->> 1)::text and d."key" = (v_after ->> 2)::text and d."id" > (v_after ->> 3)::uuid))))
      order by d."entity" desc, d."rank" collate "C" asc, d."key" asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."entity")::text, (d."key")::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."entity", d."key", d."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by d."entity" asc, d."key" asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."entity")::text, (d."key")::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."entity" <= (v_after ->> 0)::text and ((d."entity" < (v_after ->> 0)::text) or (d."entity" = (v_after ->> 0)::text and d."key" > (v_after ->> 1)::text) or (d."entity" = (v_after ->> 0)::text and d."key" = (v_after ->> 1)::text and d."id" > (v_after ->> 2)::uuid))))
      order by d."entity" desc, d."key" asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'label' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((lower(d."label"))::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (lower(d."label"), d."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(d."label") asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'label' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((lower(d."label"))::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (lower(d."label") <= (v_after ->> 0)::text and ((lower(d."label") < (v_after ->> 0)::text) or (lower(d."label") = (v_after ->> 0)::text and d."id" > (v_after ->> 1)::uuid))))
      order by lower(d."label") desc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'type' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."type"::text)::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."type"::text, d."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by d."type"::text asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'type' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."type"::text)::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."type"::text <= (v_after ->> 0)::text and ((d."type"::text < (v_after ->> 0)::text) or (d."type"::text = (v_after ->> 0)::text and d."id" > (v_after ->> 1)::uuid))))
      order by d."type"::text desc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 4) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."entity")::text, (d."rank" collate "C")::text, (d."key")::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."entity", d."rank" collate "C", d."key", d."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::text, (v_after ->> 3)::uuid))
      order by d."entity" asc, d."rank" collate "C" asc, d."key" asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  elsif v_sort = 'rank' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 4) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CUSTOM_FIELD_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) as j, jsonb_build_array((d."entity")::text, (d."rank" collate "C")::text, (d."key")::text, (d."id")::text) as k
    from (
      select * from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
        and (v_after is null or (d."entity" <= (v_after ->> 0)::text and ((d."entity" < (v_after ->> 0)::text) or (d."entity" = (v_after ->> 0)::text and d."rank" collate "C" > (v_after ->> 1)::text) or (d."entity" = (v_after ->> 0)::text and d."rank" collate "C" = (v_after ->> 1)::text and d."key" > (v_after ->> 2)::text) or (d."entity" = (v_after ->> 0)::text and d."rank" collate "C" = (v_after ->> 1)::text and d."key" = (v_after ->> 2)::text and d."id" > (v_after ->> 3)::uuid))))
      order by d."entity" desc, d."rank" collate "C" asc, d."key" asc, d."id" asc
      limit v_limit + 1 offset v_offset
    ) d
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."field_definitions" d
      where d."tenant_id" = page_field_definitions.tenant
        and (not (v_filters -> 'entity' is not null and jsonb_typeof(v_filters -> 'entity') <> 'null' and not (jsonb_typeof(v_filters -> 'entity') = 'array' and jsonb_array_length(v_filters -> 'entity') = 0)) or d."entity" = any((case when jsonb_typeof(v_filters -> 'entity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'entity')) else array[v_filters ->> 'entity'] end)::text[]))
        and (not (v_filters -> 'type' is not null and jsonb_typeof(v_filters -> 'type') <> 'null' and not (jsonb_typeof(v_filters -> 'type') = 'array' and jsonb_array_length(v_filters -> 'type') = 0)) or d."type"::text = any((case when jsonb_typeof(v_filters -> 'type') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'type')) else array[v_filters ->> 'type'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{sensitive,0}', v_filters ->> 'sensitive'), '') = 'true', false) or d."sensitive")
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or d."archived_at" is null)
        and (v_search is null or d."key" ilike v_search or d."label" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_observation_definitions (
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
  v_filters jsonb := coalesce(page_observation_definitions.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('valueType', 'scope') then
      raise exception 'facet is one of valueType, scope' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'valueType' then (x."value_type"::text)::text when 'scope' then (case when x."tenant_id" is null then 'system' else 'organization' end)::text end) as v
      from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('title', 'key') then
    raise exception 'sort is one of title, key' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."title"), x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by lower(x."title") asc, x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."key" > (v_after ->> 1)::text) or (lower(x."title") = (v_after ->> 0)::text and x."key" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by lower(x."title") desc, x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."title"), x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::text, (v_after ->> 2)::uuid))
      order by lower(x."title") asc, x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((lower(x."title"))::text, (x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (lower(x."title") <= (v_after ->> 0)::text and ((lower(x."title") < (v_after ->> 0)::text) or (lower(x."title") = (v_after ->> 0)::text and x."key" > (v_after ->> 1)::text) or (lower(x."title") = (v_after ->> 0)::text and x."key" = (v_after ->> 1)::text and x."id" > (v_after ->> 2)::uuid))))
      order by lower(x."title") desc, x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'system', x."tenant_id" is null, 'key', x."key", 'title', x."title", 'valueType', x."value_type", 'unit', x."unit", 'codeSystem', x."code_system", 'code', x."code", 'components', coalesce(x."components", '[]'::jsonb), 'decimals', x."decimals", 'validLow', x."valid_low", 'validHigh', x."valid_high", 'referenceLow', x."reference_low", 'referenceHigh', x."reference_high", 'criticalLow', x."critical_low", 'criticalHigh', x."critical_high", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
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
      select 1 from "better_supabase"."observation_definitions" x
      where (x."tenant_id" = page_observation_definitions.tenant or (x."tenant_id" is null and not exists (select 1 from "better_supabase"."observation_definitions" y where y."tenant_id" = page_observation_definitions.tenant and y."key" = x."key")))
        and (coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false) or x."archived_at" is null)
        and (not (v_filters -> 'valueType' is not null and jsonb_typeof(v_filters -> 'valueType') <> 'null' and not (jsonb_typeof(v_filters -> 'valueType') = 'array' and jsonb_array_length(v_filters -> 'valueType') = 0)) or x."value_type"::text = any((case when jsonb_typeof(v_filters -> 'valueType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'valueType')) else array[v_filters ->> 'valueType'] end)::text[]))
        and (not (v_filters -> 'scope' is not null and jsonb_typeof(v_filters -> 'scope') <> 'null' and not (jsonb_typeof(v_filters -> 'scope') = 'array' and jsonb_array_length(v_filters -> 'scope') = 0)) or case when x."tenant_id" is null then 'system' else 'organization' end = any((case when jsonb_typeof(v_filters -> 'scope') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scope')) else array[v_filters ->> 'scope'] end)::text[]))
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_observations (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_observations.filters, '{}'::jsonb);
  v_search text := null;
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'definitionKey') then
      raise exception 'facet is one of status, definitionKey' using errcode = '22023', hint = 'OBSERVATION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text when 'definitionKey' then ((select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id"))::text end) as v
      from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
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
      select 1 from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('observedAt', 'createdAt') then
    raise exception 'sort is one of observedAt, createdAt' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") as j, jsonb_build_array((x."observed_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
        and (v_after is null or (x."observed_at" >= (v_after ->> 0)::timestamptz and ((x."observed_at" > (v_after ->> 0)::timestamptz) or (x."observed_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."observed_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" < (v_after ->> 2)::uuid))))
      order by x."observed_at" asc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") as j, jsonb_build_array((x."observed_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
        and (v_after is null or (x."observed_at", x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."observed_at" desc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'observedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") as j, jsonb_build_array((x."observed_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
        and (v_after is null or (x."observed_at" >= (v_after ->> 0)::timestamptz and ((x."observed_at" > (v_after ->> 0)::timestamptz) or (x."observed_at" = (v_after ->> 0)::timestamptz and x."created_at" < (v_after ->> 1)::timestamptz) or (x."observed_at" = (v_after ->> 0)::timestamptz and x."created_at" = (v_after ->> 1)::timestamptz and x."id" < (v_after ->> 2)::uuid))))
      order by x."observed_at" asc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'observedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") as j, jsonb_build_array((x."observed_at")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
        and (v_after is null or (x."observed_at", x."created_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."observed_at" desc, x."created_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OBSERVATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'definitionId', x."definition_id", 'definitionKey', y."key", 'title', y."title", 'valueType', y."value_type", 'unit', y."unit", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'observedAt', x."observed_at", 'value', case y."value_type"
      when 'boolean' then to_jsonb(x."value_code" = 'true')
      when 'code' then to_jsonb(x."value_code")
      when 'text' then to_jsonb(x."value_text")
      when 'components' then x."components"
      else to_jsonb(x."value_number")
    end, 'flag', x."flag", 'status', x."status", 'replacesId', x."replaces_id", 'reason', x."reason", 'method', x."method", 'device', x."device", 'source', x."source", 'externalId', x."external_id", 'submissionId', x."submission_id", 'performerId', x."performer_id", 'note', x."note", 'createdAt', x."created_at") from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
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
      select 1 from "better_supabase"."observations" x
      where (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'definitionKey' is not null and jsonb_typeof(v_filters -> 'definitionKey') <> 'null' and not (jsonb_typeof(v_filters -> 'definitionKey') = 'array' and jsonb_array_length(v_filters -> 'definitionKey') = 0)) or (select y."key" from "better_supabase"."observation_definitions" y where y."id" = x."definition_id") = any((case when jsonb_typeof(v_filters -> 'definitionKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'definitionKey')) else array[v_filters ->> 'definitionKey'] end)::text[]))
        and (case when (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) then (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[])) else x."status" = 'final' end)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_time_entries (
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
  v_filters jsonb := coalesce(page_time_entries.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_everyone boolean := coalesce(nullif(coalesce(v_filters #>> '{everyone,0}', v_filters ->> 'everyone'), '') = 'true', false);
  v_user uuid := coalesce(nullif(nullif(coalesce(v_filters #>> '{userId,0}', v_filters ->> 'userId'), ''), '')::uuid, auth.uid());
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(v_user = auth.uid(), false) and not v_everyone) and coalesce(better_supabase.can('tenant', page_time_entries.tenant, 'time_entries.track'), false)) or coalesce(better_supabase.can('tenant', page_time_entries.tenant, 'time_entries.read'), false)) then
    raise exception 'not allowed to read these entries' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'billable') then
      raise exception 'facet is one of subjectType, billable' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'billable' then (x."billable"::text)::text end) as v
      from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
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
      select 1 from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startedAt', 'endedAt', 'seconds', 'createdAt') then
    raise exception 'sort is one of startedAt, endedAt, seconds, createdAt' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at" >= (v_after ->> 0)::timestamptz and ((x."started_at" > (v_after ->> 0)::timestamptz) or (x."started_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."started_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."started_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at" >= (v_after ->> 0)::timestamptz and ((x."started_at" > (v_after ->> 0)::timestamptz) or (x."started_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."started_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."started_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."started_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."started_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(x."ended_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(x."ended_at", 'infinity'::timestamptz) >= (v_after ->> 0)::timestamptz and ((coalesce(x."ended_at", 'infinity'::timestamptz) > (v_after ->> 0)::timestamptz) or (coalesce(x."ended_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(x."ended_at", 'infinity'::timestamptz) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(x."ended_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(x."ended_at", 'infinity'::timestamptz), x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."ended_at", 'infinity'::timestamptz) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'seconds' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) >= (v_after ->> 0)::bigint and ((coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) > (v_after ->> 0)::bigint) or (coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) = (v_after ->> 0)::bigint and x."id" < (v_after ->> 1)::uuid))))
      order by coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'seconds' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0), x."id") < ((v_after ->> 0)::bigint, (v_after ->> 1)::uuid))
      order by coalesce(case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 0) desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
        and (v_after is null or (x."created_at" >= (v_after ->> 0)::timestamptz and ((x."created_at" > (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."created_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'startedAt', x."started_at", 'endedAt', x."ended_at", 'seconds', case when x."ended_at" is null then null else extract(epoch from x."ended_at" - x."started_at")::bigint end, 'billable', x."billable", 'rate', x."rate"::text, 'rateCurrency', x."rate_currency", 'note', x."note", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'archivedAt', x."archived_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
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
      select 1 from "better_supabase"."time_entries" x
      where x."tenant_id" = page_time_entries.tenant
        and (v_everyone or x."user_id" = v_user)
        and (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '') is null or coalesce(x."ended_at", 'infinity'::timestamptz) > (nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), ''))::timestamptz)
        and (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '') is null or x."started_at" < (nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), ''))::timestamptz)
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'billable' is not null and jsonb_typeof(v_filters -> 'billable') <> 'null' and not (jsonb_typeof(v_filters -> 'billable') = 'array' and jsonb_array_length(v_filters -> 'billable') = 0)) or x."billable"::text = any((case when jsonb_typeof(v_filters -> 'billable') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'billable')) else array[v_filters ->> 'billable'] end)::text[]))
        and ((x."archived_at" is not null) = coalesce(nullif(coalesce(v_filters #>> '{archived,0}', v_filters ->> 'archived'), '') = 'true', false))
        and (v_search is null or x."note" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_trash (
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
  v_filters jsonb := coalesce(page_trash.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_trash.tenant, 'trash.read'), false)) then
    raise exception 'not allowed to read this organization''s trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType') then
      raise exception 'facet is one of subjectType' using errcode = '22023', hint = 'TRASH_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text end) as v
      from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
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
      select 1 from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('trashedAt', 'subjectType', 'purgeAfter') then
    raise exception 'sort is one of trashedAt, subjectType, purgeAfter' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((x."trashed_at")::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (x."trashed_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."trashed_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((x."trashed_at")::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (x."trashed_at" <= (v_after ->> 0)::timestamptz and ((x."trashed_at" < (v_after ->> 0)::timestamptz) or (x."trashed_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."trashed_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'trashedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((x."trashed_at")::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (x."trashed_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."trashed_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'trashedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((x."trashed_at")::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (x."trashed_at" <= (v_after ->> 0)::timestamptz and ((x."trashed_at" < (v_after ->> 0)::timestamptz) or (x."trashed_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."trashed_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subjectType' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((x."subject_type")::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (x."subject_type", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."subject_type" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'subjectType' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((x."subject_type")::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (x."subject_type" <= (v_after ->> 0)::text and ((x."subject_type" < (v_after ->> 0)::text) or (x."subject_type" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."subject_type" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'purgeAfter' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((coalesce(x."purge_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (coalesce(x."purge_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."purge_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'purgeAfter' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'TRASH_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'title', x."title", 'batchId', x."batch_id", 'count', x.n, 'trashedBy', x."trashed_by", 'trashedAt', x."trashed_at", 'purgeAfter', x."purge_at") as j, jsonb_build_array((coalesce(x."purge_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
        and (v_after is null or (coalesce(x."purge_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."purge_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."purge_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."purge_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from (select s.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = s."batch_id")::integer as n from "better_supabase"."trash_items" s) x
      where x."tenant_id" = page_trash.tenant
        and x."depth" = 0
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (v_search is null or x."title" ilike v_search)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tax.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'banking.read'), false)
    when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'advisories.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_vulnerabilities (
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
  v_filters jsonb := coalesce(page_vulnerabilities.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_vulnerabilities.tenant is not null and coalesce(better_supabase.can('tenant', page_vulnerabilities.tenant, 'advisories.read'), false))) then
    raise exception 'not allowed to read advisories' using errcode = '42501', hint = 'ADVISORY_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('severity') then
      raise exception 'facet is one of severity' using errcode = '22023', hint = 'ADVISORY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'severity' then (coalesce(y."severity"::text, 'none'))::text end) as v
      from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
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
      select 1 from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('vulnId', 'cvssScore', 'epssScore') then
    raise exception 'sort is one of vulnId, cvssScore, epssScore' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."vuln_id")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."vuln_id", y."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by y."vuln_id" asc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."vuln_id")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."vuln_id" <= (v_after ->> 0)::text and ((y."vuln_id" < (v_after ->> 0)::text) or (y."vuln_id" = (v_after ->> 0)::text and y."id" > (v_after ->> 1)::uuid))))
      order by y."vuln_id" desc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'vulnId' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."vuln_id")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."vuln_id", y."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by y."vuln_id" asc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'vulnId' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((y."vuln_id")::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (y."vuln_id" <= (v_after ->> 0)::text and ((y."vuln_id" < (v_after ->> 0)::text) or (y."vuln_id" = (v_after ->> 0)::text and y."id" > (v_after ->> 1)::uuid))))
      order by y."vuln_id" desc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'cvssScore' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((coalesce(y."cvss_score", -1))::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (coalesce(y."cvss_score", -1), y."id") > ((v_after ->> 0)::numeric, (v_after ->> 1)::uuid))
      order by coalesce(y."cvss_score", -1) asc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'cvssScore' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((coalesce(y."cvss_score", -1))::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (coalesce(y."cvss_score", -1) <= (v_after ->> 0)::numeric and ((coalesce(y."cvss_score", -1) < (v_after ->> 0)::numeric) or (coalesce(y."cvss_score", -1) = (v_after ->> 0)::numeric and y."id" > (v_after ->> 1)::uuid))))
      order by coalesce(y."cvss_score", -1) desc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'epssScore' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((coalesce(y."epss_score", -1))::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (coalesce(y."epss_score", -1), y."id") > ((v_after ->> 0)::numeric, (v_after ->> 1)::uuid))
      order by coalesce(y."epss_score", -1) asc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  elsif v_sort = 'epssScore' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ADVISORY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'vulnId', y."vuln_id", 'aliases', to_jsonb(y."aliases"), 'summary', y."summary", 'details', y."details", 'cvssVector', y."cvss_vector", 'cvssVersion', y."cvss_version", 'cvssScore', y."cvss_score", 'severity', y."severity", 'epssScore', y."epss_score", 'epssPercentile', y."epss_percentile", 'epssDate', y."epss_date", 'kev', y."kev", 'kevAddedOn', y."kev_added_on", 'kevDueOn', y."kev_due_on", 'kevRansomware', y."kev_ransomware", 'affectedPurls', to_jsonb(y."affected_purls"), 'references', y."reference_links", 'publishedAt', y."published_at", 'modifiedAt', y."modified_at", 'enrichedAt', y."enriched_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at") as j, jsonb_build_array((coalesce(y."epss_score", -1))::text, (y."id")::text) as k
    from (
      select * from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
        and (v_after is null or (coalesce(y."epss_score", -1) <= (v_after ->> 0)::numeric and ((coalesce(y."epss_score", -1) < (v_after ->> 0)::numeric) or (coalesce(y."epss_score", -1) = (v_after ->> 0)::numeric and y."id" > (v_after ->> 1)::uuid))))
      order by coalesce(y."epss_score", -1) desc, y."id" asc
      limit v_limit + 1 offset v_offset
    ) y
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."vulnerabilities" y
      where y."tenant_id" = page_vulnerabilities.tenant
        and (not (v_filters -> 'severity' is not null and jsonb_typeof(v_filters -> 'severity') <> 'null' and not (jsonb_typeof(v_filters -> 'severity') = 'array' and jsonb_array_length(v_filters -> 'severity') = 0)) or coalesce(y."severity"::text, 'none') = any((case when jsonb_typeof(v_filters -> 'severity') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'severity')) else array[v_filters ->> 'severity'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{kev,0}', v_filters ->> 'kev'), '') = 'true', false) or y."kev")
        and (v_search is null or y."vuln_id" ilike v_search or y."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_booking"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_booking"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_calendar"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_calendar"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_calendar_event"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_calendar_event"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_observation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_observation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_observation_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_observation_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_time_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_trash"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_trash"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_advisories"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_advisories"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_bookings"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_bookings"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_calendar_events"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_calendar_events"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_calendars"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_calendars"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_care_plans"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_care_plans"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_field_definitions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_field_definitions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_observation_definitions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_observation_definitions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_observations"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_observations"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_time_entries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_time_entries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_trash"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_trash"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_vulnerabilities"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_vulnerabilities"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_booking"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_booking"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_calendar"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_calendar"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_calendar_event"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_calendar_event"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_observation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_observation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_observation_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_observation_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_time_entry"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_time_entry"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_trash"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_trash"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_advisories"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_advisories"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_bookings"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_bookings"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_calendar_events"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_calendar_events"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_calendars"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_calendars"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_care_plans"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_care_plans"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_field_definitions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_field_definitions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_observation_definitions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_observation_definitions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_observations"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_observations"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_time_entries"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_time_entries"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_trash"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_trash"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_vulnerabilities"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_vulnerabilities"(uuid, jsonb) TO "authenticated", "service_role";
