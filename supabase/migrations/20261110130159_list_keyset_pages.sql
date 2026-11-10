SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.list_inspections (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_inspections.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_inspections.tenant is not null and coalesce(better_supabase.can('tenant', list_inspections.tenant, 'inspections.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'programId', x."program_id", 'number', x."number", 'kind', x."kind", 'title', x."title", 'scope', x."scope", 'criteria', x."criteria", 'auditee', case when x."auditee_type" is null then null else jsonb_build_object('type', x."auditee_type", 'id', x."auditee_id") end, 'leadId', x."lead_id", 'plannedStart', x."planned_start", 'plannedEnd', x."planned_end", 'startedAt', x."started_at", 'completedAt', x."completed_at", 'closedAt', x."closed_at", 'status', x."status", 'checklistFormId', x."checklist_form_id", 'checklistSubmissionId', x."checklist_submission_id", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."planned_start", '-infinity'::date))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (coalesce(x."planned_start", '-infinity'::date) <= (v_after ->> 0)::date and ((coalesce(x."planned_start", '-infinity'::date) < (v_after ->> 0)::date) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" < (v_after ->> 1)::bigint) or (coalesce(x."planned_start", '-infinity'::date) = (v_after ->> 0)::date and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."planned_start", '-infinity'::date) desc, x."sequence" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."inspections" x
      where x."tenant_id" = list_inspections.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."inspection_members" y where y."inspection_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'programId' or x."program_id" = (v_filters ->> 'programId')::uuid)
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'leadId' or x."lead_id" = (v_filters ->> 'leadId')::uuid)
        and (not v_filters ? 'from' or x."planned_start" >= (v_filters ->> 'from')::date)
        and (not v_filters ? 'to' or x."planned_start" <= (v_filters ->> 'to')::date)
        and (not v_filters ? 'auditeeType' or x."auditee_type" = v_filters ->> 'auditeeType')
        and (not v_filters ? 'auditeeId' or x."auditee_id" = v_filters ->> 'auditeeId')
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."scope" ilike v_search or x."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_meetings (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_meetings.filters, '{}'::jsonb);
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
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_meetings.tenant is not null and coalesce(better_supabase.can('tenant', list_meetings.tenant, 'meetings.read'), false)));
begin
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if not v_all and auth.uid() is null then
    raise exception 'not allowed to read meetings' using errcode = '42501', hint = 'MEETING_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'MEETING_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, (jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'kind', x."kind", 'title', x."title", 'location', x."location", 'startsAt', x."starts_at", 'endsAt', x."ends_at", 'status', x."status", 'startedAt', x."started_at", 'heldAt', x."held_at", 'summary', x."summary", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('fields', jsonb_build_object('room_code', x."room_code"))) as j, jsonb_build_array((x."starts_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'from' or x."starts_at" >= (v_filters ->> 'from')::timestamptz)
        and (not v_filters ? 'to' or x."starts_at" <= (v_filters ->> 'to')::timestamptz)
        and (not v_filters ? 'attendeeId' or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = (v_filters ->> 'attendeeId')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
        and (v_after is null or (x."starts_at" <= (v_after ->> 0)::timestamptz and ((x."starts_at" < (v_after ->> 0)::timestamptz) or (x."starts_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."starts_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."meetings" x
      where x."tenant_id" = list_meetings.tenant
        and (v_all or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = auth.uid()
        ))
        and (not v_filters ? 'kind' or x."kind" = v_filters ->> 'kind')
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'from' or x."starts_at" >= (v_filters ->> 'from')::timestamptz)
        and (not v_filters ? 'to' or x."starts_at" <= (v_filters ->> 'to')::timestamptz)
        and (not v_filters ? 'attendeeId' or exists (
          select 1 from "better_supabase"."meeting_attendees" y where y."meeting_id" = x."id" and y."user_id" = (v_filters ->> 'attendeeId')::uuid
        ))
        and (v_search is null or x."title" ilike v_search or x."location" ilike v_search or x."summary" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_risks (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_risks.filters, '{}'::jsonb);
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
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_risks.tenant is not null and coalesce(better_supabase.can('tenant', list_risks.tenant, 'risks.read'), false))) then
    raise exception 'not allowed to read risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'matrixId', x."matrix_id", 'title', x."title", 'description', x."description", 'category', x."category", 'cause', x."cause", 'consequence', x."consequence", 'ownerId', x."owner_id", 'status', x."status", 'treatment', x."treatment", 'reviewIntervalMonths', x."review_interval_months", 'nextReviewOn', x."next_review_on", 'reviewedAt', x."reviewed_at", 'inherent', case when x."inherent_score" is null then null else jsonb_build_object('likelihood', x."inherent_likelihood", 'impact', x."inherent_impact", 'score', x."inherent_score", 'band', x."inherent_band") end, 'residual', case when x."residual_score" is null then null else jsonb_build_object('likelihood', x."residual_likelihood", 'impact', x."residual_impact", 'score', x."residual_score", 'band', x."residual_band") end, 'currentAssessmentId', x."current_assessment_id", 'closedAt', x."closed_at", 'archivedAt', x."archived_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((coalesce(x."residual_score", -1))::text, (x."sequence")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when v_filters ? 'status' then x."status" = v_filters ->> 'status' else x."status" <> 'closed' end)
        and (not v_filters ? 'category' or x."category" = v_filters ->> 'category')
        and (not v_filters ? 'band' or x."residual_band" = v_filters ->> 'band')
        and (not v_filters ? 'ownerId' or x."owner_id" = (v_filters ->> 'ownerId')::uuid)
        and (coalesce((v_filters ->> 'reviewDue')::boolean, false) is false or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
        and (v_after is null or (coalesce(x."residual_score", -1) <= (v_after ->> 0)::integer and ((coalesce(x."residual_score", -1) < (v_after ->> 0)::integer) or (coalesce(x."residual_score", -1) = (v_after ->> 0)::integer and x."sequence" > (v_after ->> 1)::bigint) or (coalesce(x."residual_score", -1) = (v_after ->> 0)::integer and x."sequence" = (v_after ->> 1)::bigint and x."id" > (v_after ->> 2)::uuid))))
      order by coalesce(x."residual_score", -1) desc, x."sequence" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."risks" x
      where x."tenant_id" = list_risks.tenant
        and x."archived_at" is null
        and (case when v_filters ? 'status' then x."status" = v_filters ->> 'status' else x."status" <> 'closed' end)
        and (not v_filters ? 'category' or x."category" = v_filters ->> 'category')
        and (not v_filters ? 'band' or x."residual_band" = v_filters ->> 'band')
        and (not v_filters ? 'ownerId' or x."owner_id" = (v_filters ->> 'ownerId')::uuid)
        and (coalesce((v_filters ->> 'reviewDue')::boolean, false) is false or x."next_review_on" <= current_date)
        and (v_search is null or x."title" ilike v_search or x."number" ilike v_search or x."description" ilike v_search or x."cause" ilike v_search or x."consequence" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;


CREATE INDEX inspections_list_idx ON better_supabase.inspections USING btree (tenant_id, COALESCE(planned_start, '-infinity'::date) DESC, SEQUENCE DESC, id);

CREATE INDEX meetings_list_idx ON better_supabase.meetings USING btree (tenant_id, starts_at DESC, id);

CREATE INDEX risks_list_idx ON better_supabase.risks USING btree (tenant_id, COALESCE(residual_score, '-1'::integer) DESC, SEQUENCE, id);
