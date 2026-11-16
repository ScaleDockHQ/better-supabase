SET local check_function_bodies = off;

DROP TRIGGER "bsb_search_compliance_policy_index" ON "better_supabase"."compliance_policies";

CREATE OR REPLACE FUNCTION api.get_compliance_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_compliance_policy"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_consent_purpose (
  purpose_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_consent_purpose"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_control_framework (
  framework_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_control_framework"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_data_subject_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_data_subject_request"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_evidence_task (
  task_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_evidence_task"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_option_set (
  option_set_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_option_set"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_sequence_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_sequence_enrollment"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_support_session (
  session_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_support_session"($1) $function$;

CREATE OR REPLACE FUNCTION api.page_compliance_policies (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_compliance_policies"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_consent_purposes (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_consent_purposes"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_control_frameworks (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_control_frameworks"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_data_subject_requests (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_data_subject_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_evidence_tasks (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_evidence_tasks"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_option_sets (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_option_sets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_sequence_enrollments (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_sequence_enrollments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.page_support_sessions (
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."page_support_sessions"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_compliance_policy (
  policy_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."compliance_policies"%rowtype;
begin
  select * into v_row from "better_supabase"."compliance_policies" x where x."id" = get_compliance_policy.policy_id;
  if not found then
    raise exception 'policy not found' using errcode = 'P0002', hint = 'COMPLIANCE_POLICY_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'ownerId', v_row."owner_id", 'requiresAcknowledgement', v_row."requires_acknowledgement", 'versionId', v_row."current_version_id", 'versionNumber', v_row."version_number", 'publishedAt', v_row."published_at", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = v_row."id"::text and ack."version_id" = v_row."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = v_row."tenant_id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_consent_purpose (
  purpose_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."consent_purposes"%rowtype;
begin
  select * into v_row from "better_supabase"."consent_purposes" x where x."id" = get_consent_purpose.purpose_id;
  if not found then
    raise exception 'consent purpose not found' using errcode = 'P0002', hint = 'CONSENT_PURPOSE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."tenant_id" is null or v_row."tenant_id" in (select better_supabase.member_organization_ids())) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'title', v_row."title", 'description', v_row."description", 'legalBasis', v_row."legal_basis", 'version', v_row."version", 'requiresSignature', v_row."requires_signature", 'validMonths', v_row."valid_months", 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_control_framework (
  framework_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  select * into v_row from "better_supabase"."control_frameworks" x where x."id" = get_control_framework.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_data_subject_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."data_subject_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."data_subject_requests" x where x."id" = get_data_subject_request.request_id;
  if not found then
    raise exception 'data subject request not found' using errcode = 'P0002', hint = 'DSAR_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  return to_jsonb(v_row) || jsonb_build_object('overdue', v_row."closed_at" is null and v_row."due_at" < now());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_evidence_task (
  task_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."evidence_tasks"%rowtype;
begin
  select * into v_row from "better_supabase"."evidence_tasks" x where x."id" = get_evidence_task.task_id;
  if not found then
    raise exception 'evidence task not found' using errcode = 'P0002', hint = 'EVIDENCE_TASK_NOT_FOUND';
  end if;
  
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'controlId', v_row."control_id", 'title', v_row."title", 'assigneeId', v_row."assignee_id", 'intervalDays', v_row."interval_days", 'dueOn', v_row."due_on", 'lastCollectedAt', v_row."last_collected_at", 'active', v_row."active", 'overdue', (v_row."active" and v_row."due_on" < current_date), 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_option_set (
  option_set_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."option_sets"%rowtype;
begin
  select * into v_row from "better_supabase"."option_sets" x where x."id" = get_option_set.option_set_id;
  if not found then
    raise exception 'option set not found' using errcode = 'P0002', hint = 'OPTION_SET_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'option_sets.read'), false)) then
    raise exception 'not allowed to read option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  return to_jsonb(v_row) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = v_row."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_sequence_enrollment (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."enrollments"%rowtype;
begin
  select * into v_row from "better_supabase"."enrollments" x where x."id" = get_sequence_enrollment.enrollment_id;
  if not found then
    raise exception 'sequence enrollment not found' using errcode = 'P0002', hint = 'SEQUENCE_ENROLLMENT_NOT_FOUND';
  end if;
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'sequences.enroll'), false)))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  return "better_supabase"."sequence_member_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_support_session (
  session_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."support_sessions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('impersonation.read')) then
    raise exception 'not allowed to read support sessions' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."support_sessions" s where s."id" = get_support_session.session_id;
  if not found then
    raise exception 'support session not found' using errcode = 'P0002', hint = 'IMPERSONATION_SESSION_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'admin_id', v_row."admin_id",
    'target_user_id', v_row."target_id",
    'reason', v_row."reason",
    'tenant', v_row."tenant_id",
    'read_only', v_row."read_only",
    'started_at', v_row."started_at",
    'expires_at', v_row."expires_at",
    'ended_at', v_row."ended_at",
    'ended_by', v_row."ended_by",
    'metadata', v_row."metadata"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_compliance_policies (
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
  v_filters jsonb := coalesce(page_compliance_policies.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_compliance_policies.tenant, 'compliance.read'), false)) then
    raise exception 'not allowed to read policies' using errcode = '42501', hint = 'COMPLIANCE_POLICY_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('requiresAcknowledgement') then
      raise exception 'facet is one of requiresAcknowledgement' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
    end if;
    with s as (
      select (case v_facet when 'requiresAcknowledgement' then (x."requires_acknowledgement"::text)::text end) as v
      from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
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
      select 1 from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('title', 'publishedAt') then
    raise exception 'sort is one of title, publishedAt' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (x."title" <= (v_after ->> 0)::text and ((x."title" < (v_after ->> 0)::text) or (x."title" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."title" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((coalesce(x."published_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (coalesce(x."published_at", 'infinity'::timestamptz), x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by coalesce(x."published_at", 'infinity'::timestamptz) asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'publishedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_POLICY_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'ownerId', x."owner_id", 'requiresAcknowledgement', x."requires_acknowledgement", 'versionId', x."current_version_id", 'versionNumber', x."version_number", 'publishedAt', x."published_at", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'acknowledgedAt', (select ack."acknowledged_at" from "better_supabase"."acknowledgements" ack where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id" and ack."user_id" = auth.uid()), 'acknowledgedCount', (select count(*) from "better_supabase"."acknowledgements" ack join "public"."memberships" am on am."organization_id" = ack."tenant_id" and am."user_id" = ack."user_id" where ack."subject_type" = 'compliance_policy' and ack."subject_id" = x."id"::text and ack."version_id" = x."current_version_id"), 'memberCount', (select count(*) from "public"."memberships" pm where pm."organization_id" = x."tenant_id")) as j, jsonb_build_array((coalesce(x."published_at", 'infinity'::timestamptz))::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
        and (v_after is null or (coalesce(x."published_at", 'infinity'::timestamptz) <= (v_after ->> 0)::timestamptz and ((coalesce(x."published_at", 'infinity'::timestamptz) < (v_after ->> 0)::timestamptz) or (coalesce(x."published_at", 'infinity'::timestamptz) = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by coalesce(x."published_at", 'infinity'::timestamptz) desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."compliance_policies" x
      where x."tenant_id" = page_compliance_policies.tenant
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."title" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'ownerId' is not null and jsonb_typeof(v_filters -> 'ownerId') <> 'null' and not (jsonb_typeof(v_filters -> 'ownerId') = 'array' and jsonb_array_length(v_filters -> 'ownerId') = 0)) or x."owner_id"::text = any((case when jsonb_typeof(v_filters -> 'ownerId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'ownerId')) else array[v_filters ->> 'ownerId'] end)::text[]))
        and (not (v_filters -> 'requiresAcknowledgement' is not null and jsonb_typeof(v_filters -> 'requiresAcknowledgement') <> 'null' and not (jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' and jsonb_array_length(v_filters -> 'requiresAcknowledgement') = 0)) or x."requires_acknowledgement"::text = any((case when jsonb_typeof(v_filters -> 'requiresAcknowledgement') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'requiresAcknowledgement')) else array[v_filters ->> 'requiresAcknowledgement'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_consent_purposes (
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
  v_filters jsonb := coalesce(page_consent_purposes.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or page_consent_purposes.tenant in (select better_supabase.member_organization_ids())) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'CONSENT_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('legalBasis') then
      raise exception 'facet is one of legalBasis' using errcode = '22023', hint = 'CONSENT_INVALID';
    end if;
    with s as (
      select (case v_facet when 'legalBasis' then (x."legal_basis"::text)::text end) as v
      from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
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
      select 1 from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('key', 'createdAt') then
    raise exception 'sort is one of key, createdAt' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'legalBasis', x."legal_basis", 'version', x."version", 'requiresSignature', x."requires_signature", 'validMonths', x."valid_months", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."key" >= (v_after ->> 0)::text and ((x."key" > (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."created_at" < (v_after ->> 1)::timestamptz) or (x."key" = (v_after ->> 0)::text and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."key" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'legalBasis', x."legal_basis", 'version', x."version", 'requiresSignature', x."requires_signature", 'validMonths', x."valid_months", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."created_at" < (v_after ->> 1)::timestamptz) or (x."key" = (v_after ->> 0)::text and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."key" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'legalBasis', x."legal_basis", 'version', x."version", 'requiresSignature', x."requires_signature", 'validMonths', x."valid_months", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."key" >= (v_after ->> 0)::text and ((x."key" > (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."created_at" < (v_after ->> 1)::timestamptz) or (x."key" = (v_after ->> 0)::text and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."key" asc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'legalBasis', x."legal_basis", 'version', x."version", 'requiresSignature', x."requires_signature", 'validMonths', x."valid_months", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."key" <= (v_after ->> 0)::text and ((x."key" < (v_after ->> 0)::text) or (x."key" = (v_after ->> 0)::text and x."created_at" < (v_after ->> 1)::timestamptz) or (x."key" = (v_after ->> 0)::text and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."key" desc, x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'legalBasis', x."legal_basis", 'version', x."version", 'requiresSignature', x."requires_signature", 'validMonths', x."valid_months", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'CONSENT_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'description', x."description", 'legalBasis', x."legal_basis", 'version', x."version", 'requiresSignature', x."requires_signature", 'validMonths', x."valid_months", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
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
      select 1 from "better_supabase"."consent_purposes" x
      where (x."tenant_id" = page_consent_purposes.tenant or x."tenant_id" is null)
        and (not (v_filters -> 'key' is not null and jsonb_typeof(v_filters -> 'key') <> 'null' and not (jsonb_typeof(v_filters -> 'key') = 'array' and jsonb_array_length(v_filters -> 'key') = 0)) or x."key" = any((case when jsonb_typeof(v_filters -> 'key') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'key')) else array[v_filters ->> 'key'] end)::text[]))
        and (not (v_filters -> 'legalBasis' is not null and jsonb_typeof(v_filters -> 'legalBasis') <> 'null' and not (jsonb_typeof(v_filters -> 'legalBasis') = 'array' and jsonb_array_length(v_filters -> 'legalBasis') = 0)) or x."legal_basis"::text = any((case when jsonb_typeof(v_filters -> 'legalBasis') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'legalBasis')) else array[v_filters ->> 'legalBasis'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."key" ilike v_search or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_control_frameworks (
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
  v_filters jsonb := coalesce(page_control_frameworks.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('kind') then
      raise exception 'facet is one of kind' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
      select 1 from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('name', 'key') then
    raise exception 'sort is one of name, key' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."name" <= (v_after ->> 0)::text and ((x."name" < (v_after ->> 0)::text) or (x."name" = (v_after ->> 0)::text and x."id" > (v_after ->> 1)::uuid))))
      order by x."name" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (v_after is null or (x."key", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."key" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'key' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."key")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
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
      select 1 from "better_supabase"."control_frameworks" x
      where x."tenant_id" = page_control_frameworks.tenant
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search)
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_data_subject_requests (
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
  v_filters jsonb := coalesce(page_data_subject_requests.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_data_subject_requests.tenant, 'data_lifecycle.export'), false)) then
    raise exception 'You may not handle data subject requests here' using errcode = '42501', hint = 'DSAR_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'kind') then
      raise exception 'facet is one of status, kind' using errcode = '22023', hint = 'DSAR_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x."status"::text)::text when 'kind' then (x."kind"::text)::text end) as v
      from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
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
      select 1 from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('dueAt', 'receivedAt') then
    raise exception 'sort is one of dueAt, receivedAt' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) || jsonb_build_object('overdue', x."closed_at" is null and x."due_at" < now()) as j, jsonb_build_array((x."due_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
        and (v_after is null or (x."due_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."due_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) || jsonb_build_object('overdue', x."closed_at" is null and x."due_at" < now()) as j, jsonb_build_array((x."due_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
        and (v_after is null or (x."due_at" <= (v_after ->> 0)::timestamptz and ((x."due_at" < (v_after ->> 0)::timestamptz) or (x."due_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."due_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) || jsonb_build_object('overdue', x."closed_at" is null and x."due_at" < now()) as j, jsonb_build_array((x."due_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
        and (v_after is null or (x."due_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."due_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) || jsonb_build_object('overdue', x."closed_at" is null and x."due_at" < now()) as j, jsonb_build_array((x."due_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
        and (v_after is null or (x."due_at" <= (v_after ->> 0)::timestamptz and ((x."due_at" < (v_after ->> 0)::timestamptz) or (x."due_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."due_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'receivedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) || jsonb_build_object('overdue', x."closed_at" is null and x."due_at" < now()) as j, jsonb_build_array((x."received_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
        and (v_after is null or (x."received_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."received_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'receivedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'DSAR_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x.*) || jsonb_build_object('overdue', x."closed_at" is null and x."due_at" < now()) as j, jsonb_build_array((x."received_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
        and (v_after is null or (x."received_at" <= (v_after ->> 0)::timestamptz and ((x."received_at" < (v_after ->> 0)::timestamptz) or (x."received_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."received_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."data_subject_requests" x
      where x."tenant_id" = page_data_subject_requests.tenant
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or x."status"::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'kind' is not null and jsonb_typeof(v_filters -> 'kind') <> 'null' and not (jsonb_typeof(v_filters -> 'kind') = 'array' and jsonb_array_length(v_filters -> 'kind') = 0)) or x."kind"::text = any((case when jsonb_typeof(v_filters -> 'kind') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'kind')) else array[v_filters ->> 'kind'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{open,0}', v_filters ->> 'open'), '') = 'true', false) or x."closed_at" is null)
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."closed_at" is null and x."due_at" < now()))
        and (v_search is null or x."subject_id" ilike v_search or x."requester"::text ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_evidence_tasks (
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
  v_filters jsonb := coalesce(page_evidence_tasks.filters, '{}'::jsonb);
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
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('controlId') then
      raise exception 'facet is one of controlId' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'controlId' then (x."control_id"::text)::text end) as v
      from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
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
      select 1 from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('dueOn', 'title') then
    raise exception 'sort is one of dueOn, title' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."due_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on" <= (v_after ->> 0)::date and ((x."due_on" < (v_after ->> 0)::date) or (x."due_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."due_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."due_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'dueOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."due_on")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."due_on" <= (v_after ->> 0)::date and ((x."due_on" < (v_after ->> 0)::date) or (x."due_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."due_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
        and (v_after is null or (x."title", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."title" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'COMPLIANCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'controlId', x."control_id", 'title', x."title", 'assigneeId', x."assignee_id", 'intervalDays', x."interval_days", 'dueOn', x."due_on", 'lastCollectedAt', x."last_collected_at", 'active', x."active", 'overdue', (x."active" and x."due_on" < current_date), 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('controlCode', (select y."code" from "better_supabase"."controls" y where y."id" = x."control_id"), 'controlTitle', (select y."title" from "better_supabase"."controls" y where y."id" = x."control_id")) as j, jsonb_build_array((x."title")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
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
      select 1 from "better_supabase"."evidence_tasks" x
      where x."tenant_id" = page_evidence_tasks.tenant
        and (not (v_filters -> 'controlId' is not null and jsonb_typeof(v_filters -> 'controlId') <> 'null' and not (jsonb_typeof(v_filters -> 'controlId') = 'array' and jsonb_array_length(v_filters -> 'controlId') = 0)) or x."control_id"::text = any((case when jsonb_typeof(v_filters -> 'controlId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'controlId')) else array[v_filters ->> 'controlId'] end)::text[]))
        and (not (v_filters -> 'assigneeId' is not null and jsonb_typeof(v_filters -> 'assigneeId') <> 'null' and not (jsonb_typeof(v_filters -> 'assigneeId') = 'array' and jsonb_array_length(v_filters -> 'assigneeId') = 0)) or x."assignee_id"::text = any((case when jsonb_typeof(v_filters -> 'assigneeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'assigneeId')) else array[v_filters ->> 'assigneeId'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{overdue,0}', v_filters ->> 'overdue'), '') = 'true', false) or (x."active" and x."due_on" < current_date))
        and (v_search is null or x."title" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_option_sets (
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
  v_filters jsonb := coalesce(page_option_sets.filters, '{}'::jsonb);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', page_option_sets.tenant, 'option_sets.read'), false)) then
    raise exception 'not allowed to read option sets' using errcode = '42501', hint = 'OPTION_SET_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('subjectType', 'field') then
      raise exception 'facet is one of subjectType, field' using errcode = '22023', hint = 'OPTION_SET_INVALID';
    end if;
    with s as (
      select (case v_facet when 'subjectType' then (x."subject_type")::text when 'field' then (x."field")::text end) as v
      from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
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
      select 1 from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('createdAt', 'name') then
    raise exception 'sort is one of createdAt, name' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = x."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) as j, jsonb_build_array((x."is_default"::text)::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
        and (v_after is null or (x."is_default"::text, x."created_at", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."is_default"::text asc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = x."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) as j, jsonb_build_array((x."is_default"::text)::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
        and (v_after is null or (x."is_default"::text <= (v_after ->> 0)::text and ((x."is_default"::text < (v_after ->> 0)::text) or (x."is_default"::text = (v_after ->> 0)::text and x."created_at" > (v_after ->> 1)::timestamptz) or (x."is_default"::text = (v_after ->> 0)::text and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."is_default"::text desc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = x."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = x."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = x."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
        and (v_after is null or (x."name", x."id") > ((v_after ->> 0)::text, (v_after ->> 1)::uuid))
      order by x."name" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'name' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'OPTION_SET_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, to_jsonb(x) || jsonb_build_object('items', coalesce((
      select jsonb_agg(to_jsonb(z) order by z."rank" collate "C", z."id")
      from "better_supabase"."option_set_items" z
      where z."option_set_id" = x."id" and (false or z."archived_at" is null)
    ), '[]'::jsonb)) as j, jsonb_build_array((x."name")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
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
      select 1 from "better_supabase"."option_sets" x
      where x."tenant_id" = page_option_sets.tenant
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'field' is not null and jsonb_typeof(v_filters -> 'field') <> 'null' and not (jsonb_typeof(v_filters -> 'field') = 'array' and jsonb_array_length(v_filters -> 'field') = 0)) or x."field" = any((case when jsonb_typeof(v_filters -> 'field') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'field')) else array[v_filters ->> 'field'] end)::text[]))
        and (not (v_filters -> 'scopeId' is not null and jsonb_typeof(v_filters -> 'scopeId') <> 'null' and not (jsonb_typeof(v_filters -> 'scopeId') = 'array' and jsonb_array_length(v_filters -> 'scopeId') = 0)) or x."scope_id" = any((case when jsonb_typeof(v_filters -> 'scopeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'scopeId')) else array[v_filters ->> 'scopeId'] end)::text[]))
        and (case when (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) then (not (v_filters -> 'archived' is not null and jsonb_typeof(v_filters -> 'archived') <> 'null' and not (jsonb_typeof(v_filters -> 'archived') = 'array' and jsonb_array_length(v_filters -> 'archived') = 0)) or (x."archived_at" is not null)::text = any((case when jsonb_typeof(v_filters -> 'archived') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'archived')) else array[v_filters ->> 'archived'] end)::text[])) else x."archived_at" is null end)
        and (v_search is null or x."name" ilike v_search or x."key" ilike v_search or x."field" ilike v_search)
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_sequence_enrollments (
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
  v_filters jsonb := coalesce(page_sequence_enrollments.filters, '{}'::jsonb);
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
  if not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', page_sequence_enrollments.tenant, 'sequences.read'), false))) or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (page_sequence_enrollments.tenant is not null and coalesce(better_supabase.can('tenant', page_sequence_enrollments.tenant, 'sequences.enroll'), false)))) then
    raise exception 'not allowed to read sequences' using errcode = '42501', hint = 'SEQUENCE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status') then
      raise exception 'facet is one of status' using errcode = '22023', hint = 'SEQUENCE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then ((case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end))::text end) as v
      from "better_supabase"."enrollments" x
      where x."tenant_id" = page_sequence_enrollments.tenant and x."sequence_id" is not null
        and (not (v_filters -> 'sequenceId' is not null and jsonb_typeof(v_filters -> 'sequenceId') <> 'null' and not (jsonb_typeof(v_filters -> 'sequenceId') = 'array' and jsonb_array_length(v_filters -> 'sequenceId') = 0)) or x."sequence_id"::text = any((case when jsonb_typeof(v_filters -> 'sequenceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sequenceId')) else array[v_filters ->> 'sequenceId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
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
      where x."tenant_id" = page_sequence_enrollments.tenant and x."sequence_id" is not null
        and (not (v_filters -> 'sequenceId' is not null and jsonb_typeof(v_filters -> 'sequenceId') <> 'null' and not (jsonb_typeof(v_filters -> 'sequenceId') = 'array' and jsonb_array_length(v_filters -> 'sequenceId') = 0)) or x."sequence_id"::text = any((case when jsonb_typeof(v_filters -> 'sequenceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sequenceId')) else array[v_filters ->> 'sequenceId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('enrolledAt') then
    raise exception 'sort is one of enrolledAt' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."sequence_member_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_sequence_enrollments.tenant and x."sequence_id" is not null
        and (not (v_filters -> 'sequenceId' is not null and jsonb_typeof(v_filters -> 'sequenceId') <> 'null' and not (jsonb_typeof(v_filters -> 'sequenceId') = 'array' and jsonb_array_length(v_filters -> 'sequenceId') = 0)) or x."sequence_id"::text = any((case when jsonb_typeof(v_filters -> 'sequenceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sequenceId')) else array[v_filters ->> 'sequenceId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."enrolled_at" >= (v_after ->> 0)::timestamptz and ((x."enrolled_at" > (v_after ->> 0)::timestamptz) or (x."enrolled_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."enrolled_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."sequence_member_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_sequence_enrollments.tenant and x."sequence_id" is not null
        and (not (v_filters -> 'sequenceId' is not null and jsonb_typeof(v_filters -> 'sequenceId') <> 'null' and not (jsonb_typeof(v_filters -> 'sequenceId') = 'array' and jsonb_array_length(v_filters -> 'sequenceId') = 0)) or x."sequence_id"::text = any((case when jsonb_typeof(v_filters -> 'sequenceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sequenceId')) else array[v_filters ->> 'sequenceId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."enrolled_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."enrolled_at" desc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'enrolledAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."sequence_member_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_sequence_enrollments.tenant and x."sequence_id" is not null
        and (not (v_filters -> 'sequenceId' is not null and jsonb_typeof(v_filters -> 'sequenceId') <> 'null' and not (jsonb_typeof(v_filters -> 'sequenceId') = 'array' and jsonb_array_length(v_filters -> 'sequenceId') = 0)) or x."sequence_id"::text = any((case when jsonb_typeof(v_filters -> 'sequenceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sequenceId')) else array[v_filters ->> 'sequenceId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."enrolled_at" >= (v_after ->> 0)::timestamptz and ((x."enrolled_at" > (v_after ->> 0)::timestamptz) or (x."enrolled_at" = (v_after ->> 0)::timestamptz and x."id" < (v_after ->> 1)::uuid))))
      order by x."enrolled_at" asc, x."id" desc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'enrolledAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'SEQUENCE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, "better_supabase"."sequence_member_json"(x."id") as j, jsonb_build_array((x."enrolled_at")::text, (x."id")::text) as k
    from (
      select * from "better_supabase"."enrollments" x
      where x."tenant_id" = page_sequence_enrollments.tenant and x."sequence_id" is not null
        and (not (v_filters -> 'sequenceId' is not null and jsonb_typeof(v_filters -> 'sequenceId') <> 'null' and not (jsonb_typeof(v_filters -> 'sequenceId') = 'array' and jsonb_array_length(v_filters -> 'sequenceId') = 0)) or x."sequence_id"::text = any((case when jsonb_typeof(v_filters -> 'sequenceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sequenceId')) else array[v_filters ->> 'sequenceId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (v_after is null or (x."enrolled_at", x."id") < ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."enrolled_at" desc, x."id" desc
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
      where x."tenant_id" = page_sequence_enrollments.tenant and x."sequence_id" is not null
        and (not (v_filters -> 'sequenceId' is not null and jsonb_typeof(v_filters -> 'sequenceId') <> 'null' and not (jsonb_typeof(v_filters -> 'sequenceId') = 'array' and jsonb_array_length(v_filters -> 'sequenceId') = 0)) or x."sequence_id"::text = any((case when jsonb_typeof(v_filters -> 'sequenceId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'sequenceId')) else array[v_filters ->> 'sequenceId'] end)::text[]))
        and (not (v_filters -> 'subjectType' is not null and jsonb_typeof(v_filters -> 'subjectType') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectType') = 'array' and jsonb_array_length(v_filters -> 'subjectType') = 0)) or x."subject_type" = any((case when jsonb_typeof(v_filters -> 'subjectType') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectType')) else array[v_filters ->> 'subjectType'] end)::text[]))
        and (not (v_filters -> 'subjectId' is not null and jsonb_typeof(v_filters -> 'subjectId') <> 'null' and not (jsonb_typeof(v_filters -> 'subjectId') = 'array' and jsonb_array_length(v_filters -> 'subjectId') = 0)) or x."subject_id" = any((case when jsonb_typeof(v_filters -> 'subjectId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'subjectId')) else array[v_filters ->> 'subjectId'] end)::text[]))
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (case when x."status" = 'cancelled' then 'exited' when x."status" = 'completed' then 'completed' when x."paused_at" is not null then 'paused' else 'active' end) = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_support_sessions (
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
  v_filters jsonb := coalesce(page_support_sessions.filters, '{}'::jsonb);
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('impersonation.read')) then
    raise exception 'not allowed to read support sessions' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('readOnly') then
      raise exception 'facet is one of readOnly' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
    end if;
    with s as (
      select (case v_facet when 'readOnly' then (s."read_only"::text)::text end) as v
      from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
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
      select 1 from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startedAt', 'expiresAt') then
    raise exception 'sort is one of startedAt, expiresAt' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) as j, jsonb_build_array((s."started_at")::text, (s."id")::text) as k
    from (
      select * from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
        and (v_after is null or (s."started_at", s."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by s."started_at" asc, s."id" asc
      limit v_limit + 1 offset v_offset
    ) s
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) as j, jsonb_build_array((s."started_at")::text, (s."id")::text) as k
    from (
      select * from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
        and (v_after is null or (s."started_at" <= (v_after ->> 0)::timestamptz and ((s."started_at" < (v_after ->> 0)::timestamptz) or (s."started_at" = (v_after ->> 0)::timestamptz and s."id" > (v_after ->> 1)::uuid))))
      order by s."started_at" desc, s."id" asc
      limit v_limit + 1 offset v_offset
    ) s
  ) p;
  elsif v_sort = 'startedAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) as j, jsonb_build_array((s."started_at")::text, (s."id")::text) as k
    from (
      select * from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
        and (v_after is null or (s."started_at", s."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by s."started_at" asc, s."id" asc
      limit v_limit + 1 offset v_offset
    ) s
  ) p;
  elsif v_sort = 'startedAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) as j, jsonb_build_array((s."started_at")::text, (s."id")::text) as k
    from (
      select * from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
        and (v_after is null or (s."started_at" <= (v_after ->> 0)::timestamptz and ((s."started_at" < (v_after ->> 0)::timestamptz) or (s."started_at" = (v_after ->> 0)::timestamptz and s."id" > (v_after ->> 1)::uuid))))
      order by s."started_at" desc, s."id" asc
      limit v_limit + 1 offset v_offset
    ) s
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) as j, jsonb_build_array((s."expires_at")::text, (s."id")::text) as k
    from (
      select * from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
        and (v_after is null or (s."expires_at", s."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by s."expires_at" asc, s."id" asc
      limit v_limit + 1 offset v_offset
    ) s
  ) p;
  elsif v_sort = 'expiresAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'IMPERSONATION_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object(
    'id', s."id",
    'admin_id', s."admin_id",
    'target_user_id', s."target_id",
    'reason', s."reason",
    'tenant', s."tenant_id",
    'read_only', s."read_only",
    'started_at', s."started_at",
    'expires_at', s."expires_at",
    'ended_at', s."ended_at",
    'ended_by', s."ended_by",
    'metadata', s."metadata"
  ) as j, jsonb_build_array((s."expires_at")::text, (s."id")::text) as k
    from (
      select * from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
        and (v_after is null or (s."expires_at" <= (v_after ->> 0)::timestamptz and ((s."expires_at" < (v_after ->> 0)::timestamptz) or (s."expires_at" = (v_after ->> 0)::timestamptz and s."id" > (v_after ->> 1)::uuid))))
      order by s."expires_at" desc, s."id" asc
      limit v_limit + 1 offset v_offset
    ) s
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from "better_supabase"."support_sessions" s
      where (not (v_filters -> 'adminId' is not null and jsonb_typeof(v_filters -> 'adminId') <> 'null' and not (jsonb_typeof(v_filters -> 'adminId') = 'array' and jsonb_array_length(v_filters -> 'adminId') = 0)) or s."admin_id"::text = any((case when jsonb_typeof(v_filters -> 'adminId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'adminId')) else array[v_filters ->> 'adminId'] end)::text[]))
        and (not (v_filters -> 'targetUserId' is not null and jsonb_typeof(v_filters -> 'targetUserId') <> 'null' and not (jsonb_typeof(v_filters -> 'targetUserId') = 'array' and jsonb_array_length(v_filters -> 'targetUserId') = 0)) or s."target_id"::text = any((case when jsonb_typeof(v_filters -> 'targetUserId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'targetUserId')) else array[v_filters ->> 'targetUserId'] end)::text[]))
        and (not (v_filters -> 'tenant' is not null and jsonb_typeof(v_filters -> 'tenant') <> 'null' and not (jsonb_typeof(v_filters -> 'tenant') = 'array' and jsonb_array_length(v_filters -> 'tenant') = 0)) or s."tenant_id"::text = any((case when jsonb_typeof(v_filters -> 'tenant') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'tenant')) else array[v_filters ->> 'tenant'] end)::text[]))
        and (not coalesce(nullif(coalesce(v_filters #>> '{active,0}', v_filters ->> 'active'), '') = 'true', false) or (s."ended_at" is null and s."expires_at" > now()))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_facets jsonb;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'conversation' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."title"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."conversations" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text, s."website"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."phone"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'quote' then
      select s."tenant_id", s."title"::text, null, '/crm/quotes/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."quotes" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'ledger_account' then
      select s."tenant_id", s."name"::text, null, '/finance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."ledger_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'invoice' then
      select s."tenant_id", s."title"::text, null, '/finance/payables', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."invoices" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'rfq' then
      select s."tenant_id", s."title"::text, null, '/rfqs', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."rfqs" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'till' then
      select s."tenant_id", s."name"::text, null, '/tills', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tills" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'order' then
      select s."tenant_id", s."number"::text, null, '/shop/orders/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'booking' then
      select s."tenant_id", s."customer_name"::text, null, '/calendar', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bookings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."assets" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'asset_location' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."asset_locations" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lease' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."leases" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_report' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_reports" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'expense_line' then
      select s."tenant_id", s."description"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."expense_lines" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'donation_fund' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."donation_funds" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'warranty_claim' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."manufacturer"::text, s."decision"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."warranty_claims" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_order' then
      select s."tenant_id", s."title"::text, null, '/field/dispatch', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'shipment' then
      select s."tenant_id", s."reference"::text, null, '/field/shipments', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."shipments" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'contract' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."contracts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'control' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."controls" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'compliance_policy' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."title"::text, s."key"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."compliance_policies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'qualification_type' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."name"::text, s."key"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."qualification_types" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'inspection_program' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_programs" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection_finding' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."inspection_findings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'form' then
      select s."tenant_id", s."title"::text, null, '/forms/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."forms" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting_decision' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."meeting_decisions" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'maintenance_plan' then
      select s."tenant_id", s."title"::text, null, '/maintenance', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."maintenance_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'dam_usage_right' then
      select s."tenant_id", s."licensee"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."dam_usage_rights" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'lims_sample' then
      select s."tenant_id", s."title"::text, null, '/lims', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."lims_samples" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'tax_code' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."tax_codes" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_center' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."name"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."work_centers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'bank_account' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."name"::text, s."iban"::text, s."holder"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."bank_accounts" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'care_plan' then
      select s."tenant_id", s."title"::text, null, '/care-plans', '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."care_plans" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'incident' then
      select s."tenant_id", s."title"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."incidents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."tracking_id"::text, s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisories" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'advisory_product' then
      select s."tenant_id", s."name"::text, null, null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."advisory_products" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'vulnerability' then
      select s."tenant_id", s."vuln_id"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."vulnerabilities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'document' then
      select s."tenant_id", s."name"::text, null, '/documents/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."documents" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text, jsonb_strip_nulls(jsonb_build_object('status', s."status"))
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    when 'task' then
      select s."organization_id", s."title"::text, null, '/projects/' || s."project_id"::text, '{}'::jsonb
        into v_tenant, v_title, v_body, v_url, v_facets
        from "public"."tasks" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.recordTypes' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at", "facets", "sort_key")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now(), v_facets, left("better_supabase"."search_normalize"(v_title), 200)
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "facets" = excluded."facets",
    "sort_key" = excluded."sort_key",
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url", "better_supabase"."search_documents"."facets")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url", excluded."facets");
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE TRIGGER bsb_search_compliance_policy_index
  AFTER INSERT OR DELETE OR UPDATE OF id, tenant_id, title, key ON better_supabase.compliance_policies
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.search_index_row('compliance_policy', 'id');

REVOKE ALL ON FUNCTION "api"."get_compliance_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_compliance_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_consent_purpose"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_consent_purpose"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_control_framework"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_control_framework"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_data_subject_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_data_subject_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_evidence_task"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_evidence_task"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_option_set"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_option_set"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_sequence_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_sequence_enrollment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_support_session"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_support_session"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_compliance_policies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_compliance_policies"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_consent_purposes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_consent_purposes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_control_frameworks"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_control_frameworks"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_data_subject_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_data_subject_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_evidence_tasks"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_evidence_tasks"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_option_sets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_option_sets"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_sequence_enrollments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_sequence_enrollments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."page_support_sessions"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."page_support_sessions"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_compliance_policy"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_compliance_policy"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_consent_purpose"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_consent_purpose"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_control_framework"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_control_framework"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_data_subject_request"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_data_subject_request"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_evidence_task"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_evidence_task"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_option_set"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_option_set"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_sequence_enrollment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_sequence_enrollment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_support_session"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_support_session"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_compliance_policies"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_compliance_policies"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_consent_purposes"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_consent_purposes"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_control_frameworks"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_control_frameworks"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_data_subject_requests"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_data_subject_requests"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_evidence_tasks"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_evidence_tasks"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_option_sets"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_option_sets"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_sequence_enrollments"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_sequence_enrollments"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."page_support_sessions"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."page_support_sessions"(jsonb) TO "authenticated", "service_role";
