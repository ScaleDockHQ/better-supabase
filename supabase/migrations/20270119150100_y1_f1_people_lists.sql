SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_employee (
  employee uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_employee"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_leave_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_leave_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_document_templates (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_document_templates"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_employees (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_employees"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_leave_requests (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_leave_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_employee (
  employee uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."employees";
begin
  select * into v_row from "better_supabase"."employees" x where x."id" = get_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false) or exists (
    with recursive up (id, manager) as (
      select u."id", u."manager_id" from "better_supabase"."employees" u where u."id" = get_employee.employee
      union
      select u."id", u."manager_id" from "better_supabase"."employees" u join up on u."id" = up.manager
    )
    select 1 from up join "better_supabase"."employees" me on me."id" = up.id where me."user_id" = auth.uid())) then
    raise exception 'no such employee you can read' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_leave_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = get_leave_request.request_id;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', v_row."note", 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_deadlines (
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
  v_filters jsonb := coalesce(page_deadlines.filters, '{}'::jsonb);
  v_before date;
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', page_deadlines.tenant, 'deadlines.read'), false))) then
    raise exception 'not allowed to read deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  begin
    v_before := nullif(coalesce(v_filters #>> '{dueBefore,0}', v_filters ->> 'dueBefore'), '')::date;
  exception when others then
    raise exception 'dueBefore must be a date' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('state', 'result', 'groupKey') then
      raise exception 'facet is one of state, result, groupKey' using errcode = '22023', hint = 'DEADLINE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'state' then (z."state"::text)::text when 'result' then (z."result"::text)::text when 'groupKey' then (z."group_key")::text end) as v
      from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
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
      select 1 from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('dueOn', 'createdAt') then
    raise exception 'sort is one of dueOn, createdAt' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'jurisdiction', z."jurisdiction", 'kind', z."kind", 'groupKey', z."group_key", 'ruleKey', z."rule_key", 'period', z."period", 'ruleVersionId', z."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = z."rule_version_id"), 'facts', z."facts", 'result', z."result", 'dueOn', z."due_on", 'provisional', z."provisional", 'missing', to_jsonb(z."missing"), 'exception', z."exception", 'review', z."review", 'basis', z."basis", 'deadline', z."deadline", 'citation', z."citation", 'asOf', z."as_of", 'state', z."state", 'satisfiedAt', z."satisfied_at", 'satisfiedBy', z."satisfied_by", 'satisfiedAction', z."satisfied_action", 'computedAt', z."computed_at", 'createdAt', z."created_at") as j, jsonb_build_array((coalesce(z."due_on", 'infinity'::date))::text, (z."created_at")::text, (z."id")::text) as k
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
        and (v_after is null or (coalesce(z."due_on", 'infinity'::date), z."created_at", z."id") > ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by coalesce(z."due_on", 'infinity'::date) asc, z."created_at" asc, z."id" asc
      limit v_limit + 1 offset v_offset
    ) z
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'jurisdiction', z."jurisdiction", 'kind', z."kind", 'groupKey', z."group_key", 'ruleKey', z."rule_key", 'period', z."period", 'ruleVersionId', z."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = z."rule_version_id"), 'facts', z."facts", 'result', z."result", 'dueOn', z."due_on", 'provisional', z."provisional", 'missing', to_jsonb(z."missing"), 'exception', z."exception", 'review', z."review", 'basis', z."basis", 'deadline', z."deadline", 'citation', z."citation", 'asOf', z."as_of", 'state', z."state", 'satisfiedAt', z."satisfied_at", 'satisfiedBy', z."satisfied_by", 'satisfiedAction', z."satisfied_action", 'computedAt', z."computed_at", 'createdAt', z."created_at") as j, jsonb_build_array((coalesce(z."due_on", 'infinity'::date))::text, (z."created_at")::text, (z."id")::text) as k
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
        and (v_after is null or (coalesce(z."due_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(z."due_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(z."due_on", 'infinity'::date) = (v_after ->> 0)::date and z."created_at" > (v_after ->> 1)::timestamptz) or (coalesce(z."due_on", 'infinity'::date) = (v_after ->> 0)::date and z."created_at" = (v_after ->> 1)::timestamptz and z."id" > (v_after ->> 2)::uuid))))
      order by coalesce(z."due_on", 'infinity'::date) desc, z."created_at" asc, z."id" asc
      limit v_limit + 1 offset v_offset
    ) z
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'jurisdiction', z."jurisdiction", 'kind', z."kind", 'groupKey', z."group_key", 'ruleKey', z."rule_key", 'period', z."period", 'ruleVersionId', z."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = z."rule_version_id"), 'facts', z."facts", 'result', z."result", 'dueOn', z."due_on", 'provisional', z."provisional", 'missing', to_jsonb(z."missing"), 'exception', z."exception", 'review', z."review", 'basis', z."basis", 'deadline', z."deadline", 'citation', z."citation", 'asOf', z."as_of", 'state', z."state", 'satisfiedAt', z."satisfied_at", 'satisfiedBy', z."satisfied_by", 'satisfiedAction', z."satisfied_action", 'computedAt', z."computed_at", 'createdAt', z."created_at") as j, jsonb_build_array((coalesce(z."due_on", 'infinity'::date))::text, (z."created_at")::text, (z."id")::text) as k
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
        and (v_after is null or (coalesce(z."due_on", 'infinity'::date), z."created_at", z."id") > ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by coalesce(z."due_on", 'infinity'::date) asc, z."created_at" asc, z."id" asc
      limit v_limit + 1 offset v_offset
    ) z
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'jurisdiction', z."jurisdiction", 'kind', z."kind", 'groupKey', z."group_key", 'ruleKey', z."rule_key", 'period', z."period", 'ruleVersionId', z."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = z."rule_version_id"), 'facts', z."facts", 'result', z."result", 'dueOn', z."due_on", 'provisional', z."provisional", 'missing', to_jsonb(z."missing"), 'exception', z."exception", 'review', z."review", 'basis', z."basis", 'deadline', z."deadline", 'citation', z."citation", 'asOf', z."as_of", 'state', z."state", 'satisfiedAt', z."satisfied_at", 'satisfiedBy', z."satisfied_by", 'satisfiedAction', z."satisfied_action", 'computedAt', z."computed_at", 'createdAt', z."created_at") as j, jsonb_build_array((coalesce(z."due_on", 'infinity'::date))::text, (z."created_at")::text, (z."id")::text) as k
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
        and (v_after is null or (coalesce(z."due_on", 'infinity'::date) <= (v_after ->> 0)::date and ((coalesce(z."due_on", 'infinity'::date) < (v_after ->> 0)::date) or (coalesce(z."due_on", 'infinity'::date) = (v_after ->> 0)::date and z."created_at" > (v_after ->> 1)::timestamptz) or (coalesce(z."due_on", 'infinity'::date) = (v_after ->> 0)::date and z."created_at" = (v_after ->> 1)::timestamptz and z."id" > (v_after ->> 2)::uuid))))
      order by coalesce(z."due_on", 'infinity'::date) desc, z."created_at" asc, z."id" asc
      limit v_limit + 1 offset v_offset
    ) z
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'jurisdiction', z."jurisdiction", 'kind', z."kind", 'groupKey', z."group_key", 'ruleKey', z."rule_key", 'period', z."period", 'ruleVersionId', z."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = z."rule_version_id"), 'facts', z."facts", 'result', z."result", 'dueOn', z."due_on", 'provisional', z."provisional", 'missing', to_jsonb(z."missing"), 'exception', z."exception", 'review', z."review", 'basis', z."basis", 'deadline', z."deadline", 'citation', z."citation", 'asOf', z."as_of", 'state', z."state", 'satisfiedAt', z."satisfied_at", 'satisfiedBy', z."satisfied_by", 'satisfiedAction', z."satisfied_action", 'computedAt', z."computed_at", 'createdAt', z."created_at") as j, jsonb_build_array((z."created_at")::text, (z."id")::text) as k
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
        and (v_after is null or (z."created_at" >= (v_after ->> 0)::timestamptz and ((z."created_at" > (v_after ->> 0)::timestamptz) or (z."created_at" = (v_after ->> 0)::timestamptz and z."id" < (v_after ->> 1)::uuid))))
      order by z."created_at" asc, z."id" desc
      limit v_limit + 1 offset v_offset
    ) z
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'jurisdiction', z."jurisdiction", 'kind', z."kind", 'groupKey', z."group_key", 'ruleKey', z."rule_key", 'period', z."period", 'ruleVersionId', z."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = z."rule_version_id"), 'facts', z."facts", 'result', z."result", 'dueOn', z."due_on", 'provisional', z."provisional", 'missing', to_jsonb(z."missing"), 'exception', z."exception", 'review', z."review", 'basis', z."basis", 'deadline', z."deadline", 'citation', z."citation", 'asOf', z."as_of", 'state', z."state", 'satisfiedAt', z."satisfied_at", 'satisfiedBy', z."satisfied_by", 'satisfiedAction', z."satisfied_action", 'computedAt', z."computed_at", 'createdAt', z."created_at") as j, jsonb_build_array((z."created_at")::text, (z."id")::text) as k
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
        and (v_after is null or (z."created_at", z."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by z."created_at" desc, z."id" desc
      limit v_limit + 1 offset v_offset
    ) z
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."deadlines" z
      where z."tenant_id" = page_deadlines.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or z."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or z."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'groupKey' is not null and jsonb_typeof(v_filters -> 'groupKey') <> 'null' and not (jsonb_typeof(v_filters -> 'groupKey') = 'array' and jsonb_array_length(v_filters -> 'groupKey') = 0)) or z."group_key" = any((case when jsonb_typeof(v_filters -> 'groupKey') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'groupKey')) else array[v_filters ->> 'groupKey'] end)::text[]))
        and (not (v_filters -> 'period' is not null and jsonb_typeof(v_filters -> 'period') <> 'null' and not (jsonb_typeof(v_filters -> 'period') = 'array' and jsonb_array_length(v_filters -> 'period') = 0)) or z."period" = any((case when jsonb_typeof(v_filters -> 'period') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'period')) else array[v_filters ->> 'period'] end)::text[]))
        and (not (v_filters -> 'state' is not null and jsonb_typeof(v_filters -> 'state') <> 'null' and not (jsonb_typeof(v_filters -> 'state') = 'array' and jsonb_array_length(v_filters -> 'state') = 0)) or z."state"::text = any((case when jsonb_typeof(v_filters -> 'state') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'state')) else array[v_filters ->> 'state'] end)::text[]))
        and (not (v_filters -> 'result' is not null and jsonb_typeof(v_filters -> 'result') <> 'null' and not (jsonb_typeof(v_filters -> 'result') = 'array' and jsonb_array_length(v_filters -> 'result') = 0)) or z."result"::text = any((case when jsonb_typeof(v_filters -> 'result') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'result')) else array[v_filters ->> 'result'] end)::text[]))
        and (not (v_filters -> 'provisional' is not null and jsonb_typeof(v_filters -> 'provisional') <> 'null' and not (jsonb_typeof(v_filters -> 'provisional') = 'array' and jsonb_array_length(v_filters -> 'provisional') = 0)) or z."provisional"::text = any((case when jsonb_typeof(v_filters -> 'provisional') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'provisional')) else array[v_filters ->> 'provisional'] end)::text[]))
        and (v_before is null or z."due_on" < v_before)
        and (v_search is null or z."kind" ilike v_search or z."jurisdiction" ilike v_search or z."subject_id" ilike v_search or z."group_key" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_document_templates (
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
  v_filters jsonb := coalesce(page_document_templates.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('documentType', 'active', 'language') then
      raise exception 'facet is one of documentType, active, language' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'documentType' then (t."document_type")::text when 'active' then (t."active"::text)::text when 'language' then (t."language")::text end) as v
      from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
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
      select 1 from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'updatedAt') then
    raise exception 'sort is one of name, updatedAt' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") as j, jsonb_build_array((t."name")::text, (t."id")::text) as k
    from (
      select * from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
        and (v_after is null or (t."name", t."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by t."name" asc, t."id" asc
      limit v_limit + 1 offset v_offset
    ) t
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") as j, jsonb_build_array((t."name")::text, (t."id")::text) as k
    from (
      select * from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
        and (v_after is null or (t."name" <= (v_after ->> 0)::text and ((t."name" < (v_after ->> 0)::text) or (t."name" = (v_after ->> 0)::text and t."id" > (v_after ->> 1)::uuid))))
      order by t."name" desc, t."id" asc
      limit v_limit + 1 offset v_offset
    ) t
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") as j, jsonb_build_array((t."name")::text, (t."id")::text) as k
    from (
      select * from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
        and (v_after is null or (t."name", t."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by t."name" asc, t."id" asc
      limit v_limit + 1 offset v_offset
    ) t
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") as j, jsonb_build_array((t."name")::text, (t."id")::text) as k
    from (
      select * from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
        and (v_after is null or (t."name" <= (v_after ->> 0)::text and ((t."name" < (v_after ->> 0)::text) or (t."name" = (v_after ->> 0)::text and t."id" > (v_after ->> 1)::uuid))))
      order by t."name" desc, t."id" asc
      limit v_limit + 1 offset v_offset
    ) t
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") as j, jsonb_build_array((t."updated_at")::text, (t."id")::text) as k
    from (
      select * from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
        and (v_after is null or (t."updated_at", t."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by t."updated_at" asc, t."id" asc
      limit v_limit + 1 offset v_offset
    ) t
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") as j, jsonb_build_array((t."updated_at")::text, (t."id")::text) as k
    from (
      select * from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
        and (v_after is null or (t."updated_at" <= (v_after ->> 0)::timestamptz and ((t."updated_at" < (v_after ->> 0)::timestamptz) or (t."updated_at" = (v_after ->> 0)::timestamptz and t."id" > (v_after ->> 1)::uuid))))
      order by t."updated_at" desc, t."id" asc
      limit v_limit + 1 offset v_offset
    ) t
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."document_templates" t
      where t."tenant_id" = page_document_templates.tenant
        and (not (v_filters -> 'documentType' is not null and jsonb_typeof(v_filters -> 'documentType') <> 'null' and not (jsonb_typeof(v_filters -> 'documentType') = 'array' and jsonb_array_length(v_filters -> 'documentType') = 0)) or t."document_type" = any((case when jsonb_typeof(v_filters -> 'documentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'documentType')) else array[v_filters ->> 'documentType'] end)::text[]))
        and (not (v_filters -> 'legalEntityId' is not null and jsonb_typeof(v_filters -> 'legalEntityId') <> 'null' and not (jsonb_typeof(v_filters -> 'legalEntityId') = 'array' and jsonb_array_length(v_filters -> 'legalEntityId') = 0)) or t."legal_entity_id" = any((case when jsonb_typeof(v_filters -> 'legalEntityId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalEntityId')) else array[v_filters ->> 'legalEntityId'] end)::uuid[]))
        and (not (v_filters -> 'language' is not null and jsonb_typeof(v_filters -> 'language') <> 'null' and not (jsonb_typeof(v_filters -> 'language') = 'array' and jsonb_array_length(v_filters -> 'language') = 0)) or coalesce(t."language", '') = any((case when jsonb_typeof(v_filters -> 'language') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'language')) else array[v_filters ->> 'language'] end)::text[]))
        and (not (v_filters -> 'active' is not null and jsonb_typeof(v_filters -> 'active') <> 'null' and not (jsonb_typeof(v_filters -> 'active') = 'array' and jsonb_array_length(v_filters -> 'active') = 0)) or t."active"::text = any((case when jsonb_typeof(v_filters -> 'active') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'active')) else array[v_filters ->> 'active'] end)::text[]))
        and (v_search is null or t."name" ilike v_search or t."document_type" ilike v_search or t."body" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_employees (
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
  v_filters jsonb := coalesce(page_employees.filters, '{}'::jsonb);
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', page_employees.tenant, 'employees.read'), false)) then
    raise exception 'not allowed to read the employees' using errcode = '42501', hint = 'EMPLOYEE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'employmentType', 'teamId') then
      raise exception 'facet is one of status, employmentType, teamId' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status")::text when 'employmentType' then (x."employment_type")::text when 'teamId' then (x."team_id"::text)::text end) as v
      from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
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
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'startDate') then
    raise exception 'sort is one of name, startDate' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name"), x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by lower(x."name") asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((lower(x."name"))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (lower(x."name") <= (v_after ->> 0)::text and ((lower(x."name") < (v_after ->> 0)::text) or (lower(x."name") = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by lower(x."name") desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01'), x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by coalesce(x."start_date", date '0001-01-01') asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startDate' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'EMPLOYEE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) as j, jsonb_build_array((coalesce(x."start_date", date '0001-01-01'))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
        and (v_after is null or (coalesce(x."start_date", date '0001-01-01') <= (v_after ->> 0)::date and ((coalesce(x."start_date", date '0001-01-01') < (v_after ->> 0)::date) or (coalesce(x."start_date", date '0001-01-01') = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."start_date", date '0001-01-01') desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."employees" x
      where x."tenant_id" = page_employees.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status" = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'employmentType' is not null and jsonb_typeof(v_filters -> 'employmentType') <> 'null' and not (jsonb_typeof(v_filters -> 'employmentType') = 'array' and jsonb_array_length(v_filters -> 'employmentType') = 0)) or x."employment_type" = any((case when jsonb_typeof(v_filters -> 'employmentType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'employmentType')) else array[v_filters ->> 'employmentType'] end)::text[]))
        and (not (v_filters -> 'teamId' is not null and jsonb_typeof(v_filters -> 'teamId') <> 'null' and not (jsonb_typeof(v_filters -> 'teamId') = 'array' and jsonb_array_length(v_filters -> 'teamId') = 0)) or x."team_id" = any((case when jsonb_typeof(v_filters -> 'teamId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'teamId')) else array[v_filters ->> 'teamId'] end)::uuid[]))
        and (not (v_filters -> 'managerId' is not null and jsonb_typeof(v_filters -> 'managerId') <> 'null' and not (jsonb_typeof(v_filters -> 'managerId') = 'array' and jsonb_array_length(v_filters -> 'managerId') = 0)) or x."manager_id" = any((case when jsonb_typeof(v_filters -> 'managerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'managerId')) else array[v_filters ->> 'managerId'] end)::uuid[]))
        and (not (v_filters -> 'userId' is not null and jsonb_typeof(v_filters -> 'userId') <> 'null' and not (jsonb_typeof(v_filters -> 'userId') = 'array' and jsonb_array_length(v_filters -> 'userId') = 0)) or x."user_id" = any((case when jsonb_typeof(v_filters -> 'userId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'userId')) else array[v_filters ->> 'userId'] end)::uuid[]))
        and (v_search is null or x."name" ilike v_search or x."email" ilike v_search or x."job_title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_enrollments (
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
  v_filters jsonb := coalesce(page_enrollments.filters, '{}'::jsonb);
  v_read boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', page_enrollments.tenant, 'enrollments.read'), false)));
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
  if not v_read and auth.uid() is null then
    raise exception 'not allowed to read enrollments' using errcode = '42501', hint = 'ENROLLMENTS_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'program') then
      raise exception 'facet is one of status, program' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text when 'program' then (x."program")::text end) as v
      from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
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
      select 1 from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('updatedAt', 'enrolledAt') then
    raise exception 'sort is one of updatedAt, enrolledAt' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
        and (v_after is null or (x."updated_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."updated_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'updatedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."updated_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
        and (v_after is null or (x."updated_at" <= (v_after ->> 0)::timestamptz and ((x."updated_at" < (v_after ->> 0)::timestamptz) or (x."updated_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."updated_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'enrolledAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
        and (v_after is null or (x."enrolled_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."enrolled_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'enrolledAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'ENROLLMENTS_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."enrollment_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
        and (v_after is null or (x."enrolled_at" <= (v_after ->> 0)::timestamptz and ((x."enrolled_at" < (v_after ->> 0)::timestamptz) or (x."enrolled_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."enrolled_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."enrollments" x
      where x."tenant_id" = page_enrollments.tenant
        and (v_read or x."user_id" = auth.uid())
        and (not (v_filters -> 'program' is not null and jsonb_typeof(v_filters -> 'program') <> 'null' and not (jsonb_typeof(v_filters -> 'program') = 'array' and jsonb_array_length(v_filters -> 'program') = 0)) or x."program" = any((case when jsonb_typeof(v_filters -> 'program') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'program')) else array[v_filters ->> 'program'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_search is null or x."program" ilike v_search or x."subject_id" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_leave_requests (
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
  v_filters jsonb := coalesce(page_leave_requests.filters, '{}'::jsonb);
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_leave_requests.tenant, 'leave.read'), false);
  v_everyone boolean := coalesce(nullif(coalesce(v_filters #>> '{everyone,0}', v_filters ->> 'everyone'), '')::boolean, false);
  v_user_arg uuid := nullif(coalesce(v_filters #>> '{userId,0}', v_filters ->> 'userId'), '')::uuid;
  v_employee_arg uuid := nullif(coalesce(v_filters #>> '{employeeId,0}', v_filters ->> 'employeeId'), '')::uuid;
  v_from date := nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date;
  v_to date := nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date;
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
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
  if not (v_reader or coalesce(better_supabase.can('tenant', page_leave_requests.tenant, 'leave.request'), false)) then
    raise exception 'not allowed to list leave requests' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if not v_reader and (v_everyone or (v_user_arg is not null and v_user_arg is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'typeId') then
      raise exception 'facet is one of status, typeId' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x.leave_status)::text when 'typeId' then (x."type_id"::text)::text end) as v
      from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
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
      select 1 from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on", x."created_at", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" > (v_after ->> 1)::timestamptz) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on", x."created_at", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" > (v_after ->> 1)::timestamptz) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."ends_on")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."ends_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."ends_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."ends_on")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."ends_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', x."note", 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
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
      select 1 from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x.leave_status = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or x."note" ilike v_search or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_employee"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_employee"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_leave_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_leave_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_document_templates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_document_templates"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_employees"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_employees"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_leave_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_leave_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_employee"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_employee"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_leave_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_leave_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_document_templates"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_document_templates"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_employees"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_employees"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_leave_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_leave_requests"(uuid, jsonb) TO "authenticated", "service_role";
