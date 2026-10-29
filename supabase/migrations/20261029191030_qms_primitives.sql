SET local check_function_bodies = off;

DROP FUNCTION "api"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text);

DROP FUNCTION "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid);

DROP FUNCTION "api"."save_control_framework"(uuid, text, text, text, text);

DROP FUNCTION "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text);

DROP FUNCTION "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid);

DROP FUNCTION "better_supabase"."save_control_framework"(uuid, text, text, text, text);

ALTER TABLE "better_supabase"."control_frameworks"
  ADD COLUMN "kind" text NOT NULL DEFAULT 'standard'::text;

ALTER TABLE "better_supabase"."controls"
  ADD COLUMN "source" text;

ALTER TABLE "better_supabase"."controls"
  ADD COLUMN "jurisdiction" text;

ALTER TABLE "better_supabase"."course_certificates"
  ADD COLUMN "expires_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."courses"
  ADD COLUMN "valid_for_months" integer;

ALTER TABLE "better_supabase"."signature_requests"
  ADD COLUMN "meaning" text;

CREATE OR REPLACE FUNCTION api.create_signature_request (
  tenant              uuid,
  subject_type        text,
  subject_id          text,
  signers             uuid[],
  version_id          uuid   DEFAULT NULL::uuid,
  sign_order          text   DEFAULT 'parallel'::text,
  approval_request_id uuid   DEFAULT NULL::uuid,
  message             text   DEFAULT NULL::text,
  meaning             text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_signature_request"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.organization_setting (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_setting"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_control (
  framework_id uuid,
  code         text,
  title        text,
  description  text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  applicable   boolean DEFAULT true,
  control_id   uuid    DEFAULT NULL::uuid,
  source       text    DEFAULT NULL::text,
  jurisdiction text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_control"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.save_control_framework (
  tenant      uuid,
  key         text,
  name        text,
  version     text DEFAULT NULL::text,
  description text DEFAULT NULL::text,
  kind        text DEFAULT 'standard'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_control_framework"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.add_employee_contract (
  employee uuid,
  attrs    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_employee "better_supabase"."employees";
  v_row "better_supabase"."employee_contracts";
  v_starts date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_employee from "better_supabase"."employees" x where x."id" = add_employee_contract.employee;
  if v_employee."id" is null or not ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.write'), false) and coalesce(better_supabase.can('tenant', v_employee."tenant_id", 'employees.view_sensitive'), false))) then
    raise exception 'no such employee whose details you can see' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  begin
    v_starts := (add_employee_contract.attrs ->> 'startsOn')::date;
    if v_starts is null then
      raise exception 'a contract needs a start date' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."employee_contracts" x where x."employee_id" = v_employee."id" and x."starts_on" >= v_starts) then
      raise exception 'a new contract starts after the latest one' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_OVERLAP';
    end if;
    update "better_supabase"."employee_contracts" x set "ends_on" = v_starts - 1
    where x."employee_id" = v_employee."id" and (x."ends_on" is null or x."ends_on" >= v_starts);
    insert into "better_supabase"."employee_contracts" ("tenant_id", "employee_id", "starts_on", "ends_on", "hours_per_week", "salary", "currency", "salary_period", "note", "created_by")
    values (v_employee."tenant_id", v_employee."id", v_starts, (add_employee_contract.attrs ->> 'endsOn')::date, (add_employee_contract.attrs ->> 'hoursPerWeek')::numeric, (add_employee_contract.attrs ->> 'salary')::bigint, upper(add_employee_contract.attrs ->> 'currency'), add_employee_contract.attrs ->> 'salaryPeriod', nullif(trim(add_employee_contract.attrs ->> 'note'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a contract field has an invalid value' using errcode = '22023', hint = 'EMPLOYEE_CONTRACT_INVALID';
  end;
  perform "better_supabase".emit_event('employee.updated', jsonb_build_object('organizationId', v_employee."tenant_id", 'employeeId', v_employee."id", 'subjectType', 'employee', 'subjectId', v_employee."id"::text, 'name', v_employee."name", 'userId', v_employee."user_id", 'fields', jsonb_build_array('contract')), 'employees/' || v_employee."id"::text, (v_employee."tenant_id"::text)::text, null, 'better-supabase/employees');
  return to_jsonb(v_row) || jsonb_build_object('salary', v_row."salary"::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = cancel_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.manage'), false)) then
    raise exception 'not allowed to cancel this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'cancelled', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  perform "better_supabase".emit_event('signature.cancelled', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.cancelled',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'cancelled a signature request',
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id")
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.course_finish (
  enrollment_id uuid,
  was           text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_enrollment record;
  v_certificate "better_supabase"."course_certificates";
begin
  select x."id" as id, x."tenant_id" as tenant, x."status" as status, x."user_id" as learner, y."id" as course, y."issues_certificate" as certifies, y."valid_for_months"::integer as valid_for
  into v_enrollment
  from "better_supabase"."enrollments" x join "better_supabase"."courses" y on ('course:' || y."id"::text) = x."program"
  where x."id" = course_finish.enrollment_id;
  if v_enrollment.id is null or v_enrollment.status <> 'completed' then
    return;
  end if;
  if course_finish.was is distinct from 'completed' then
    perform "better_supabase".emit_event('course.completed', jsonb_build_object('organizationId', v_enrollment.tenant, 'id', v_enrollment.course, 'userId', v_enrollment.learner, 'enrollmentId', v_enrollment.id), 'courses/' || v_enrollment.course::text, (v_enrollment.tenant)::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course.completed',
    category => 'data',
    target_type => 'course',
    record_id => v_enrollment.course::text,
    target_label => v_enrollment.learner::text,
    summary => 'completed a course',
    tenant => (v_enrollment.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_enrollment.tenant, 'id', v_enrollment.course, 'userId', v_enrollment.learner, 'enrollmentId', v_enrollment.id)
  );
  end if;
  if v_enrollment.certifies then
    insert into "better_supabase"."course_certificates" ("tenant_id", "course_id", "enrollment_id", "user_id", "code", "expires_at")
    values (v_enrollment.tenant, v_enrollment.course, v_enrollment.id, v_enrollment.learner, encode(extensions.gen_random_bytes(16), 'hex'), now() + make_interval(months => v_enrollment.valid_for))
    on conflict on constraint "course_certificates_enrollment_key" do nothing
    returning * into v_certificate;
    if v_certificate."id" is not null then
      perform "better_supabase".emit_event('course_certificate.issued', jsonb_build_object('organizationId', v_certificate."tenant_id", 'id', v_certificate."id", 'courseId', v_certificate."course_id", 'userId', v_certificate."user_id", 'enrollmentId', v_certificate."enrollment_id", 'expiresAt', v_certificate."expires_at"), 'course-certificates/' || v_certificate."id"::text, (v_certificate."tenant_id")::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course_certificate.issued',
    category => 'data',
    target_type => 'course_certificate',
    record_id => v_certificate."id"::text,
    target_label => v_certificate."code",
    summary => 'issued a course certificate',
    tenant => (v_certificate."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_certificate."tenant_id", 'id', v_certificate."id", 'courseId', v_certificate."course_id", 'userId', v_certificate."user_id", 'enrollmentId', v_certificate."enrollment_id", 'expiresAt', v_certificate."expires_at")
  );
    end if;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.course_json (
  course_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'validForMonths', x."valid_for_months", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."courses" x where x."id" = course_json.course_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.course_learner_json (
  enrollment_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'enrollmentId', x."id", 'courseId', substr(x."program", 8)::uuid, 'organizationId', x."tenant_id", 'userId', x."user_id",
    'status', x."status", 'completedLessons', x."completed_steps", 'totalLessons', cardinality(x."steps"),
    'enrolledAt', x."enrolled_at", 'completedAt', x."completed_at", 'cancelledAt', x."cancelled_at", 'updatedAt', x."updated_at",
    'lessons', coalesce((
      select jsonb_agg(jsonb_build_object('lessonId', y."lesson_id", 'startedAt', y."started_at", 'completedAt', y."completed_at", 'attempts', y."attempts", 'submissionId', y."submission_id", 'score', y."score", 'maxScore', y."max_score", 'passed', y."passed") order by y."started_at", y."lesson_id")
      from "better_supabase"."course_lesson_progress" y where y."enrollment_id" = x."id"
    ), '[]'::jsonb),
    'certificate', (select jsonb_build_object('id', z."id", 'courseId', z."course_id", 'userId', z."user_id", 'code', z."code", 'issuedAt', z."issued_at", 'expiresAt', z."expires_at", 'revokedAt', z."revoked_at") from "better_supabase"."course_certificates" z where z."enrollment_id" = x."id")
  )
  from "better_supabase"."enrollments" x
  where x."id" = course_learner_json.enrollment_id
$function$;

CREATE OR REPLACE FUNCTION better_supabase.course_outline (
  course_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_course "better_supabase"."courses";
  v_row "better_supabase"."enrollments";
begin
  select * into v_course from "better_supabase"."courses" x where x."id" = course_outline.course_id;
  if v_course."id" is null or not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.manage'), false)))
    or (v_course."status" = 'published' and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_course."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_course."tenant_id", 'courses.read'), false))))
    or exists (select 1 from "better_supabase"."enrollments" y where y."tenant_id" = v_course."tenant_id" and y."program" = ('course:' || v_course."id"::text)
      and y."subject_type" = 'user' and y."subject_id" = auth.uid()::text and y."status" <> 'cancelled')) then
    raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."enrollments" x
  where x."tenant_id" = v_course."tenant_id" and x."program" = ('course:' || v_course."id"::text)
    and x."subject_type" = 'user' and x."subject_id" = auth.uid()::text;
  return jsonb_build_object('id', v_course."id", 'organizationId', v_course."tenant_id", 'key', v_course."key", 'title', v_course."title", 'summary', v_course."summary", 'status', v_course."status", 'certificate', v_course."issues_certificate", 'validForMonths', v_course."valid_for_months", 'createdBy', v_course."created_by", 'createdAt', v_course."created_at", 'updatedAt', v_course."updated_at") || jsonb_build_object(
    'modules', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'title', z."title", 'rank', z."rank", 'lessons', coalesce((
        select jsonb_agg(jsonb_build_object('id', y."id", 'moduleId', y."module_id", 'title', y."title", 'kind', y."kind", 'required', y."required",
          'minutes', y."duration_minutes", 'rank', y."rank", 'completedAt', (
            select w."completed_at" from "better_supabase"."course_lesson_progress" w where w."enrollment_id" = v_row."id" and w."lesson_id" = y."id"
          )) order by y."rank", y."id")
        from "better_supabase"."course_lessons" y where y."module_id" = z."id"
      ), '[]'::jsonb)) order by z."rank", z."id")
      from "better_supabase"."course_modules" z where z."course_id" = v_course."id"
    ), '[]'::jsonb),
    'progress', case when v_row."id" is null then null else "better_supabase"."course_learner_json"(v_row."id") end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_signature_request (
  tenant              uuid,
  subject_type        text,
  subject_id          text,
  signers             uuid[],
  version_id          uuid   DEFAULT NULL::uuid,
  sign_order          text   DEFAULT 'parallel'::text,
  approval_request_id uuid   DEFAULT NULL::uuid,
  message             text   DEFAULT NULL::text,
  meaning             text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_version uuid := create_signature_request.version_id;
  v_hash text;
  v_row "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'signatures.request'), false) and case create_signature_request.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    else false
  end)) then
    raise exception 'not allowed to request signatures on this record' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
  end if;
  if create_signature_request.sign_order not in ('parallel', 'sequential') then
    raise exception 'sign_order must be parallel or sequential' using errcode = '22023', hint = 'SIGNATURE_ORDER_INVALID';
  end if;
  if coalesce(cardinality(create_signature_request.signers), 0) not between 1 and 20
    or array_position(create_signature_request.signers, null) is not null
    or (select count(distinct x) from unnest(create_signature_request.signers) x) <> cardinality(create_signature_request.signers) then
    raise exception 'name between 1 and 20 different signers' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if exists (
    select 1 from unnest(create_signature_request.signers) x
    where not exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
    )
  ) then
    raise exception 'every signer must be a member of the organization' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if create_signature_request.approval_request_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" a
    where a."id" = create_signature_request.approval_request_id
      and a."tenant_id" = create_signature_request.tenant
      and a."subject_type" = create_signature_request.subject_type
      and a."subject_id" = create_signature_request.subject_id
  ) then
    raise exception 'the approval request isn''t for this record' using errcode = '22023', hint = 'SIGNATURE_APPROVAL_NOT_FOUND';
  end if;
  if v_version is null then
    v_version := ("better_supabase"."snapshot_version"(create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id) ->> 'id')::uuid;
  end if;
  select x."content_hash" into v_hash
    from "better_supabase"."versions" x
    where x."id" = v_version
      and x."tenant_id" = create_signature_request.tenant
      and x."subject_type" = create_signature_request.subject_type
      and x."subject_id" = create_signature_request.subject_id;
  if v_hash is null then
    raise exception 'the version isn''t a version of this record' using errcode = '22023', hint = 'SIGNATURE_VERSION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_request"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version;
    end if;
  end;
  update "better_supabase"."versions" x set "frozen" = true where x."id" = v_version and not x."frozen";
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('signature.requested', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id"), 'signature-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.requested',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_row."id"::text,
    summary => 'requested signatures on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decline_signature_request (
  request_id uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
  v_req "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = decline_signature_request.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if v_me is null or not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  update "better_supabase"."signature_requests" x set "status" = 'declined', "completed_at" = now()
    where x."id" = v_req."id"
    returning * into v_req;
  perform "better_supabase".emit_event('signature.declined', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.declined',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'declined to sign' || coalesce(': ' || left(decline_signature_request.reason, 200), ''),
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signer', v_me)
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_control (
  control_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."controls"%rowtype;
begin
  select * into v_row from "better_supabase"."controls" x where x."id" = get_control.control_id;
  if not found then
    raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'evidence', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'evidenceTaskId', y."task_id", 'attachmentId', y."attachment_id", 'note', y."note", 'collectedBy', y."collected_by", 'collectedAt', y."collected_at", 'validUntil', y."valid_until", 'valid', (y."valid_until" is null or y."valid_until" >= current_date)) order by y."collected_at" desc), '[]'::jsonb)
      from (select * from "better_supabase"."control_evidence" z where z."control_id" = v_row."id" order by z."collected_at" desc limit 100) y),
    'tasks', (select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'controlId', y."control_id", 'title', y."title", 'assigneeId', y."assignee_id", 'intervalDays', y."interval_days", 'dueOn', y."due_on", 'lastCollectedAt', y."last_collected_at", 'active', y."active", 'overdue', (y."active" and y."due_on" < current_date), 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."due_on"), '[]'::jsonb)
      from "better_supabase"."evidence_tasks" y where y."control_id" = v_row."id")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
  v_items jsonb;
begin
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = get_signature_request.request_id;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and case v_req."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    else false
  end)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_control_frameworks (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'kind', x."kind", 'version', x."version", 'description', x."description", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."control_frameworks" x
  where x."tenant_id" = list_control_frameworks.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_controls (
  tenant       uuid,
  framework_id uuid    DEFAULT NULL::uuid,
  status       text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  page_size    integer DEFAULT 200
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(x.doc order by x.framework, x.code), '[]'::jsonb)
  from (
    select y."framework_id" as framework, y."code" as code, jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'frameworkId', y."framework_id", 'code', y."code", 'title', y."title", 'description', y."description", 'ownerId', y."owner_id", 'applicable', y."applicable", 'source', y."source", 'jurisdiction', y."jurisdiction", 'status', case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end, 'createdAt', y."created_at", 'updatedAt', y."updated_at") as doc
    from "better_supabase"."controls" y
    where y."tenant_id" = list_controls.tenant
      and (list_controls.framework_id is null or y."framework_id" = list_controls.framework_id)
      and (list_controls.owner_id is null or y."owner_id" = list_controls.owner_id)
      and (list_controls.status is null or case
    when not y."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = y."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = y."id") then 'failing'
    else 'not_started'
  end = list_controls.status)
    order by y."framework_id", y."code"
    limit least(greatest(coalesce(list_controls.page_size, 200), 1), 1000)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_courses (
  tenant uuid,
  status text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_manage boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_courses.tenant is not null and coalesce(better_supabase.can('tenant', list_courses.tenant, 'courses.manage'), false)));
begin
  if not (v_manage or (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_courses.tenant is not null and coalesce(better_supabase.can('tenant', list_courses.tenant, 'courses.read'), false)))) then
    raise exception 'not allowed to read courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if list_courses.status is not null and list_courses.status not in ('draft', 'published', 'archived') then
    raise exception 'status must be draft, published or archived' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'title', x."title", 'summary', x."summary", 'status', x."status", 'certificate', x."issues_certificate", 'validForMonths', x."valid_for_months", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."title", x."id")
    from "better_supabase"."courses" x
    where x."tenant_id" = list_courses.tenant
      and (v_manage or x."status" = 'published')
      and (list_courses.status is null or x."status" = list_courses.status)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_signature_requests (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  mine         boolean                  DEFAULT false,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or list_signature_requests.mine or coalesce(better_supabase.can('tenant', list_signature_requests.tenant, 'signatures.read'), false)) then
    raise exception 'not allowed to list signature requests' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."signature_requests" x
    where x."tenant_id" = list_signature_requests.tenant
      and (list_signature_requests.subject_type is null or x."subject_type" = list_signature_requests.subject_type)
      and (list_signature_requests.subject_id is null or x."subject_id" = list_signature_requests.subject_id)
      and (list_signature_requests.status is null or x."status" = list_signature_requests.status)
      and (list_signature_requests.before is null or x."created_at" < list_signature_requests.before)
      and (not list_signature_requests.mine or auth.uid() = any (x."signers"))
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
    order by x."created_at" desc
    limit least(greatest(coalesce(list_signature_requests.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.offboard_employee (
  employee uuid,
  end_date date,
  reason   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."employees";
  v_report "better_supabase"."employees";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."employees" x where x."id" = offboard_employee.employee;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.write'), false)) then
    raise exception 'no such employee you can offboard' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
  end if;
  if v_row."status" = 'offboarded' then
    return to_jsonb(v_row);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  begin
    update "better_supabase"."employees" x set "status" = 'offboarded', "end_date" = coalesce(offboard_employee.end_date, current_date), "offboard_reason" = nullif(trim(offboard_employee.reason), ''), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation then
    raise exception 'the end date is before the start date' using errcode = '22023', hint = 'EMPLOYEE_ATTRS_INVALID';
  end;
  for v_report in select * from "better_supabase"."employees" x where x."manager_id" = v_row."id" loop
    update "better_supabase"."employees" x set "manager_id" = v_row."manager_id", "updated_at" = now()
    where x."id" = v_report."id"
    returning * into v_report;
    perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_report."tenant_id", 'employeeId', v_report."id", 'subjectType', 'employee', 'subjectId', v_report."id"::text, 'name', v_report."name", 'userId', v_report."user_id", 'fromManagerId', v_row."id", 'toManagerId', v_report."manager_id"), 'employees/' || v_report."id"::text, (v_report."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = now()
  where x."employee_id" = v_row."id";
  perform "better_supabase".emit_event('employee.offboarded', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'endDate', v_row."end_date", 'reason', v_row."offboard_reason"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_offboard"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_setting (
  tenant uuid,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select s."value"
  from "better_supabase"."organization_settings" s
  where s."organization_id" = organization_setting.tenant and s."key" = organization_setting.key
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_control (
  framework_id uuid,
  code         text,
  title        text,
  description  text    DEFAULT NULL::text,
  owner_id     uuid    DEFAULT NULL::uuid,
  applicable   boolean DEFAULT true,
  control_id   uuid    DEFAULT NULL::uuid,
  source       text    DEFAULT NULL::text,
  jurisdiction text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_framework "better_supabase"."control_frameworks"%rowtype;
  v_row "better_supabase"."controls"%rowtype;
  v_new boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_framework from "better_supabase"."control_frameworks" x where x."id" = save_control.framework_id;
  if not found then
    raise exception 'framework not found' using errcode = 'P0002', hint = 'CONTROL_FRAMEWORK_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_framework."tenant_id", 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if nullif(trim(save_control.code), '') is null or nullif(trim(save_control.title), '') is null then
    raise exception 'a control needs a code and a title' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.owner_id is not null and not exists (select 1 from "public"."memberships" m where m."organization_id" = v_framework."tenant_id" and m."user_id" = save_control.owner_id) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  if save_control.control_id is null then
    insert into "better_supabase"."controls" ("tenant_id", "framework_id", "code", "title", "description", "owner_id", "source", "jurisdiction", "applicable")
    values (v_framework."tenant_id", v_framework."id", trim(save_control.code), trim(save_control.title), nullif(trim(save_control.description), ''), save_control.owner_id, nullif(trim(save_control.source), ''), nullif(trim(save_control.jurisdiction), ''), coalesce(save_control.applicable, true))
    on conflict ("framework_id", "code") do update
      set "title" = excluded."title", "description" = excluded."description", "source" = excluded."source", "jurisdiction" = excluded."jurisdiction",
        "owner_id" = excluded."owner_id", "applicable" = excluded."applicable", "updated_at" = now()
    returning * into v_row;
  else
    update "better_supabase"."controls" x set "code" = trim(save_control.code), "title" = trim(save_control.title),
      "description" = nullif(trim(save_control.description), ''), "source" = nullif(trim(save_control.source), ''), "jurisdiction" = nullif(trim(save_control.jurisdiction), ''), "owner_id" = save_control.owner_id,
      "applicable" = coalesce(save_control.applicable, true), "updated_at" = now()
      where x."id" = save_control.control_id and x."framework_id" = v_framework."id"
      returning * into v_row;
    if not found then
      raise exception 'control not found' using errcode = 'P0002', hint = 'CONTROL_NOT_FOUND';
    end if;
  end if;
  perform "better_supabase".emit_event('control.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code"), 'controls/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/compliance');
  perform better_supabase.audit_event(
    event_type => 'control.saved',
    category => 'data',
    target_type => 'control',
    record_id => v_row."id"::text,
    summary => 'saved control ' || v_row."code",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'controlId', v_row."id", 'frameworkId', v_row."framework_id", 'code', v_row."code")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'frameworkId', v_row."framework_id", 'code', v_row."code", 'title', v_row."title", 'description', v_row."description", 'ownerId', v_row."owner_id", 'applicable', v_row."applicable", 'source', v_row."source", 'jurisdiction', v_row."jurisdiction", 'status', case
    when not v_row."applicable" then 'not_applicable'
    when exists (select 1 from "better_supabase"."evidence_tasks" st where st."control_id" = v_row."id" and (st."active" and st."due_on" < current_date)) then 'failing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id" and (se."valid_until" is null or se."valid_until" >= current_date)) then 'passing'
    when exists (select 1 from "better_supabase"."control_evidence" se where se."control_id" = v_row."id") then 'failing'
    else 'not_started'
  end, 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_control_framework (
  tenant      uuid,
  key         text,
  name        text,
  version     text DEFAULT NULL::text,
  description text DEFAULT NULL::text,
  kind        text DEFAULT 'standard'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."control_frameworks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_control_framework.tenant, 'controls.manage'), false)) then
    raise exception 'not allowed to manage controls' using errcode = '42501', hint = 'CONTROLS_FORBIDDEN';
  end if;
  if save_control_framework.kind is null or save_control_framework.kind not in ('standard', 'legal', 'internal', 'contract') then
    raise exception 'kind must be one of standard, legal, internal, contract' using errcode = '22023', hint = 'CONTROLS_INVALID';
  end if;
  insert into "better_supabase"."control_frameworks" ("tenant_id", "key", "name", "kind", "version", "description")
  values (save_control_framework.tenant, save_control_framework.key, trim(save_control_framework.name), save_control_framework.kind, nullif(trim(save_control_framework.version), ''), nullif(trim(save_control_framework.description), ''))
  on conflict ("tenant_id", "key") do update
    set "name" = excluded."name", "kind" = excluded."kind", "version" = excluded."version",
      "description" = excluded."description", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'kind', v_row."kind", 'version', v_row."version", 'description', v_row."description", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_course (
  tenant uuid,
  course jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."courses";
  v_row "better_supabase"."courses";
  v_key text;
  v_title text;
  v_summary text;
  v_status text;
  v_certificate boolean;
  v_valid_for integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_course.tenant is not null and coalesce(better_supabase.can('tenant', save_course.tenant, 'courses.manage'), false))) then
    raise exception 'not allowed to manage courses' using errcode = '42501', hint = 'COURSE_FORBIDDEN';
  end if;
  if save_course.course is null or jsonb_typeof(save_course.course) <> 'object' then
    raise exception 'course must be an object' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  v_id := nullif(save_course.course ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."courses" x where x."id" = v_id and x."tenant_id" = save_course.tenant for update;
    if v_old."id" is null then
      raise exception 'course not found' using errcode = 'P0002', hint = 'COURSE_NOT_FOUND';
    end if;
  end if;
  v_key := coalesce(save_course.course ->> 'key', v_old."key");
  v_title := trim(coalesce(save_course.course ->> 'title', v_old."title"));
  v_summary := case when save_course.course ? 'summary' then nullif(trim(save_course.course ->> 'summary'), '') else v_old."summary" end;
  v_status := coalesce(save_course.course ->> 'status', v_old."status", 'draft');
  v_certificate := case when save_course.course ? 'certificate' then (save_course.course ->> 'certificate')::boolean else coalesce(v_old."issues_certificate", true) end;
  v_valid_for := v_old."valid_for_months";
  if save_course.course ? 'validForMonths' then
    if jsonb_typeof(save_course.course -> 'validForMonths') = 'null' then
      v_valid_for := null;
    elsif jsonb_typeof(save_course.course -> 'validForMonths') <> 'number'
      or (save_course.course ->> 'validForMonths')::numeric % 1 <> 0
      or (save_course.course ->> 'validForMonths')::numeric not between 1 and 240 then
      raise exception 'validForMonths must be a whole number of months from 1 to 240, or null' using errcode = '22023', hint = 'COURSE_INVALID';
    else
      v_valid_for := (save_course.course ->> 'validForMonths')::integer;
    end if;
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9-]{0,62}$' then
    raise exception 'key: use lowercase letters, digits or "-", starting with a letter' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_title is null or length(v_title) not between 1 and 200 then
    raise exception 'title must be 1 to 200 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if length(v_summary) > 2000 then
    raise exception 'summary must be at most 2000 characters' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_status not in ('draft', 'published', 'archived') then
    raise exception 'status must be draft, published or archived' using errcode = '22023', hint = 'COURSE_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."courses" ("tenant_id", "key", "title", "summary", "status", "issues_certificate", "valid_for_months", "created_by")
    values (save_course.tenant, v_key, v_title, v_summary, v_status, v_certificate, v_valid_for, auth.uid())
    on conflict ("tenant_id", "key") do nothing
    returning * into v_row;
    if v_row."id" is null then
      raise exception 'a course with this key already exists' using errcode = '23505', hint = 'COURSE_EXISTS';
    end if;
  else
    begin
      update "better_supabase"."courses" x
      set "key" = v_key, "title" = v_title, "summary" = v_summary, "status" = v_status,
        "issues_certificate" = v_certificate,
        "valid_for_months" = v_valid_for, "updated_at" = now()
      where x."id" = v_old."id"
      returning * into v_row;
    exception when unique_violation then
      raise exception 'a course with this key already exists' using errcode = '23505', hint = 'COURSE_EXISTS';
    end;
  end if;
  perform "better_supabase".emit_event('course.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status"), 'courses/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/courses');
  perform better_supabase.audit_event(
    event_type => 'course.saved',
    category => 'data',
    target_type => 'course',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'saved a course',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'status', v_row."status")
  );
  return "better_supabase"."course_json"(v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_signature (
  request_id          uuid,
  method              text,
  typed_name          text DEFAULT NULL::text,
  image_attachment_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_req "better_supabase"."signature_requests"%rowtype;
  v_row "better_supabase"."signatures"%rowtype;
  v_typed text := nullif(trim(sign_signature.typed_name), '');
  v_current text;
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to sign' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if sign_signature.method not in ('drawn', 'typed', 'click') then
    raise exception 'method must be drawn, typed or click' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'typed' and v_typed is null then
    raise exception 'a typed signature needs the typed name' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  if sign_signature.method = 'drawn' and sign_signature.image_attachment_id is null then
    raise exception 'a drawn signature needs its image attachment' using errcode = '22023', hint = 'SIGNATURE_METHOD_INVALID';
  end if;
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = sign_signature.request_id for update;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (v_me = any (v_req."signers")) then
    raise exception 'not a signer on this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'SIGNATURE_REQUEST_CLOSED';
  end if;
  if exists (select 1 from "better_supabase"."signatures" g where g."request_id" = v_req."id" and g."signer" = v_me) then
    raise exception 'you already signed this request' using errcode = '23505', hint = 'SIGNATURE_ALREADY_SIGNED';
  end if;
  select count(*) into v_count from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  if v_req."sign_order" = 'sequential' and array_position(v_req."signers", v_me) <> v_count + 1 then
    raise exception 'an earlier signer hasn''t signed yet' using errcode = '55000', hint = 'SIGNATURE_OUT_OF_ORDER';
  end if;
  if sign_signature.image_attachment_id is not null and not exists (
    select 1 from "better_supabase"."attachments" a
    where a."id" = sign_signature.image_attachment_id
      and a."organization_id" = v_req."tenant_id"
  ) then
    raise exception 'the signature image isn''t an attachment in this organization' using errcode = '22023', hint = 'SIGNATURE_IMAGE_NOT_FOUND';
  end if;
  select encode(extensions.digest(coalesce(x."content"::text, '') || coalesce(x."storage_path", ''), 'sha256'), 'hex') into v_current
    from "better_supabase"."versions" x where x."id" = v_req."version_id";
  if v_current is distinct from v_req."content_hash" then
    raise exception 'the version to sign changed after the request was made' using errcode = '55000', hint = 'SIGNATURE_CONTENT_CHANGED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_sign"(uuid, uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text)', v_hook::oid::regproc)
        using v_req."id", v_me, sign_signature.method;
    end if;
  end;
  insert into "better_supabase"."signatures" ("request_id", "tenant_id", "signer", "method", "typed_name", "image_attachment_id", "signed_hash", "ip", "user_agent", "signed_at")
  values (v_req."id", v_req."tenant_id", v_me, sign_signature.method, v_typed, sign_signature.image_attachment_id,
    encode(extensions.digest(v_req."id"::text || ':' || v_req."content_hash" || ':' || v_me::text || ':' || sign_signature.method || ':' || coalesce(v_typed, '') || ':' || coalesce(sign_signature.image_attachment_id::text, '') || ':' || to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), 'sha256'), 'hex'),
    left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64),
    left(v_headers ->> 'user-agent', 512),
    v_at)
  returning * into v_row;
  perform "better_supabase".emit_event('signature.signed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.signed',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_req."id"::text,
    summary => 'signed ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'signatureId', v_row."id", 'signer', v_me, 'method', v_row."method")
  );
  -- A signer who approves the linked request's current step decides it.
  if v_req."approval_request_id" is not null and "better_supabase"."approval_eligible"(v_req."approval_request_id") then
    perform "better_supabase"."decide_approval"(v_req."approval_request_id", 'approved', 'Signed electronically');
  end if;
  if v_count + 1 >= cardinality(v_req."signers") then
    update "better_supabase"."signature_requests" x set "status" = 'completed', "completed_at" = v_at
      where x."id" = v_req."id"
      returning * into v_req;
    perform "better_supabase".emit_event('signature.completed', jsonb_build_object('organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'versionId', v_req."version_id", 'meaning', v_req."meaning"), 'signature-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/signatures');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_sign"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'requestId', v_row."request_id", 'signer', v_row."signer", 'method', v_row."method", 'typedName', v_row."typed_name", 'imageAttachmentId', v_row."image_attachment_id", 'signedHash', v_row."signed_hash", 'ip', v_row."ip", 'userAgent', v_row."user_agent", 'signedAt', v_row."signed_at") || jsonb_build_object('requestStatus', v_req."status");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_employees (
  changes jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_change jsonb;
  v_id uuid;
  v_field text;
  v_row "better_supabase"."employees";
  v_was "better_supabase"."employees";
  v_accepted jsonb := '[]';
  v_rejected jsonb := '[]';
  v_hint text;
  v_reason text;
  v_state text;
  v_touched uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(coalesce(update_employees.changes, '[]')) <> 'array' then
    raise exception 'changes must be a list of { employeeId, field, value }' using errcode = '22023', hint = 'EMPLOYEE_CHANGES_INVALID';
  end if;
  for v_change in select value from jsonb_array_elements(update_employees.changes) loop
    v_field := v_change ->> 'field';
    begin
      v_id := (v_change ->> 'employeeId')::uuid;
      select * into v_was from "better_supabase"."employees" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.write'), false));
      if v_was."id" is null then
        raise exception 'no such employee you can edit' using errcode = 'P0002', hint = 'EMPLOYEE_NOT_FOUND';
      end if;
      declare
    v_hook regprocedure := to_regprocedure('"public"."before_employee_update"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using v_id, v_field, v_change -> 'value';
    end if;
  end;
      case v_field
      when 'name' then
        update "better_supabase"."employees" x set "name" = trim(v_change -> 'value' #>> '{}'), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'email' then
        update "better_supabase"."employees" x set "email" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'userId' then
        update "better_supabase"."employees" x set "user_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'jobTitle' then
        update "better_supabase"."employees" x set "job_title" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'teamId' then
        update "better_supabase"."employees" x set "team_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'managerId' then
        update "better_supabase"."employees" x set "manager_id" = (v_change -> 'value' #>> '{}')::uuid, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'employmentType' then
        update "better_supabase"."employees" x set "employment_type" = nullif(trim(v_change -> 'value' #>> '{}'), ''), "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'startDate' then
        update "better_supabase"."employees" x set "start_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'endDate' then
        update "better_supabase"."employees" x set "end_date" = (v_change -> 'value' #>> '{}')::date, "updated_at" = now() where x."id" = v_id returning * into v_row;
      when 'status' then
        if (v_change ->> 'value') not in ('preboarding', 'active', 'on_leave') then
          raise exception 'status is preboarding, active or on_leave; offboard to end employment' using errcode = '22023', hint = 'EMPLOYEE_STATUS_INVALID';
        end if;
        update "better_supabase"."employees" x set "status" = v_change ->> 'value', "updated_at" = now() where x."id" = v_id returning * into v_row;
        if v_was."status" = 'offboarded' then
          update "better_supabase"."employees" x set "end_date" = null, "offboard_reason" = null where x."id" = v_id returning * into v_row;
  update "better_supabase"."employee_private_details" x set "offboarded_at" = null
  where x."employee_id" = v_id;
          null;
        end if;
      else
        raise exception 'that field can''t be written' using errcode = '22023', hint = 'EMPLOYEE_FIELD_UNKNOWN';
      end case;
      if v_field = 'name' and nullif(v_row."name", '') is null then
        raise exception 'an employee needs a name' using errcode = '23502', hint = 'EMPLOYEE_ATTRS_INVALID';
      end if;
  if not (v_row."employment_type" = any (array['employee', 'contractor', 'intern', 'temporary']::text[])) then
    raise exception 'unknown employment type' using errcode = '22023', hint = 'EMPLOYEE_TYPE_INVALID';
  end if;
      if v_field = 'userId' then
  if v_row."user_id" is not null and not exists (
    select 1 from "public"."memberships" m
    where m."organization_id" = v_row."tenant_id" and m."user_id" = v_row."user_id"
  ) then
    raise exception 'the user is not a member of this organization' using errcode = '22023', hint = 'EMPLOYEE_USER_NOT_MEMBER';
  end if;
        null;
      end if;
      if v_row."manager_id" is distinct from v_was."manager_id" then
        perform "better_supabase".emit_event('employee.manager_changed', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'fromManagerId', v_was."manager_id", 'toManagerId', v_row."manager_id"), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
      end if;
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object('employeeId', v_id, 'field', v_field));
      v_touched := array_append(v_touched, v_id);
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_employee_update"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_id, v_field;
    end if;
  end;
    exception when others then
      get stacked diagnostics v_hint = pg_exception_hint, v_reason = message_text, v_state = returned_sqlstate;
      if v_state = '23505' then
        v_hint := 'EMPLOYEE_USER_TAKEN';
      elsif nullif(v_hint, '') is null and v_state in ('23514', '23502', '22P02', '22007', '22008') then
        v_hint := 'EMPLOYEE_ATTRS_INVALID';
      end if;
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object('employeeId', v_change ->> 'employeeId', 'field', v_field, 'hint', nullif(v_hint, ''), 'reason', v_reason));
    end;
  end loop;
  for v_row in select * from "better_supabase"."employees" x where x."id" = any (v_touched) loop
    perform "better_supabase".emit_event('employee.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'employeeId', v_row."id", 'subjectType', 'employee', 'subjectId', v_row."id"::text, 'name', v_row."name", 'userId', v_row."user_id", 'fields', (select jsonb_agg(distinct a ->> 'field') from jsonb_array_elements(v_accepted) a where (a ->> 'employeeId')::uuid = v_row."id")), 'employees/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/employees');
  end loop;
  return jsonb_build_object('accepted', v_accepted, 'rejected', v_rejected);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.verify_course_certificate (
  code text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', z."id", 'courseId', z."course_id", 'courseTitle', y."title", 'organizationId', z."tenant_id",
    'issuedAt', z."issued_at", 'expiresAt', z."expires_at", 'revokedAt', z."revoked_at",
    'expired', coalesce(z."expires_at" <= now(), false), 'valid', z."revoked_at" is null and not coalesce(z."expires_at" <= now(), false))
  from "better_supabase"."course_certificates" z join "better_supabase"."courses" y on y."id" = z."course_id"
  where z."code" = lower(verify_course_certificate.code)
$function$;

ALTER TABLE "better_supabase"."control_frameworks"
  ADD CONSTRAINT "control_frameworks_kind_check" CHECK ((kind = ANY (ARRAY['standard'::text, 'legal'::text, 'internal'::text, 'contract'::text])));

ALTER TABLE "better_supabase"."controls"
  ADD CONSTRAINT "controls_jurisdiction_check" CHECK (((jurisdiction IS NULL) OR ((length(jurisdiction) >= 1) AND (length(jurisdiction) <= 200))));

ALTER TABLE "better_supabase"."controls"
  ADD CONSTRAINT "controls_source_check" CHECK (((source IS NULL) OR ((length(source) >= 1) AND (length(source) <= 200))));

ALTER TABLE "better_supabase"."courses"
  ADD CONSTRAINT "courses_valid_for_months_check" CHECK (((valid_for_months IS NULL) OR ((valid_for_months >= 1) AND (valid_for_months <= 240))));

REVOKE ALL ON FUNCTION "api"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."organization_setting"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."organization_setting"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_control_framework"(uuid, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_control_framework"(uuid, text, text, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_signature_request"(uuid, text, text, uuid[], uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_setting"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_setting"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_control"(uuid, text, text, text, uuid, boolean, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_control_framework"(uuid, text, text, text, text, text) TO "authenticated", "service_role";
