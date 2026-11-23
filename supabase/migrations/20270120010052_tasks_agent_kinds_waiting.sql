SET local check_function_bodies = off;

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
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."maintenance_requests" x
      where x."tenant_id" = page_maintenance_requests.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
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
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."number")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((lower(x."title"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((coalesce(x."due_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."work_items" x
      where x."tenant_id" = page_work_items.tenant
        and x."archived_at" is null
        and true
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
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
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or (x."state")::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'priority' is not null and jsonb_typeof(v_filters -> 'priority') <> 'null' and not (jsonb_typeof(v_filters -> 'priority') = 'array' and jsonb_array_length(v_filters -> 'priority') = 0)) or x."priority"::text = any((case when jsonb_typeof(v_filters -> 'priority') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'priority')) else array[v_filters ->> 'priority'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'projectId' is not null and jsonb_typeof(v_filters -> 'projectId') <> 'null' and not (jsonb_typeof(v_filters -> 'projectId') = 'array' and jsonb_array_length(v_filters -> 'projectId') = 0)) or x."project_id" = any((case when jsonb_typeof(v_filters -> 'projectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'projectId')) else array[v_filters ->> 'projectId'] end)::uuid[]))
        and (not (v_filters -> 'iterationId' is not null and jsonb_typeof(v_filters -> 'iterationId') <> 'null' and not (jsonb_typeof(v_filters -> 'iterationId') = 'array' and jsonb_array_length(v_filters -> 'iterationId') = 0)) or x."iteration_id" = any((case when jsonb_typeof(v_filters -> 'iterationId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'iterationId')) else array[v_filters ->> 'iterationId'] end)::uuid[]))
        and (not (v_filters -> 'parentId' is not null and jsonb_typeof(v_filters -> 'parentId') <> 'null' and not (jsonb_typeof(v_filters -> 'parentId') = 'array' and jsonb_array_length(v_filters -> 'parentId') = 0)) or x."parent_id" = any((case when jsonb_typeof(v_filters -> 'parentId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'parentId')) else array[v_filters ->> 'parentId'] end)::uuid[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or y."user_id" = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::uuid[]))))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{ready,0}', v_filters ->> 'ready'), '') = 'true', false) or (x."waiting_on" = 0 and x."closed_at" is null))
        and (not coalesce(nullif(coalesce(v_filters #>> '{waiting,0}', v_filters ->> 'waiting'), '') = 'true', false) or (x."waiting_on" > 0 and x."closed_at" is null))
        and (v_search is null or x."title" ilike v_search or x."identifier" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;
