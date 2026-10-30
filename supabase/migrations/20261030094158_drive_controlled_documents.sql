SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."status_history";

DROP POLICY "status_history_read" ON "better_supabase"."status_history";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."status_stages";

DROP POLICY "status_stages_read" ON "better_supabase"."status_stages";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."subject_lifecycles";

DROP POLICY "subject_lifecycles_read" ON "better_supabase"."subject_lifecycles";

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "document_number" text;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "document_type" text;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "document_status" text;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "document_owner_id" uuid;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "effective_version_id" uuid;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "effective_from" timestamp WITH time zone;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "review_interval_months" integer;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "next_review_on" date;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD COLUMN "review_notified_for" date;

CREATE OR REPLACE FUNCTION api.drive_document_obsolete (
  node   uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_document_obsolete"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_document_release (
  node       uuid,
  attachment uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_document_release"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.drive_document_review (
  node    uuid,
  outcome text,
  note    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_document_review"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_document_save (
  node                   uuid,
  document_type          text,
  owner_id               uuid    DEFAULT NULL::uuid,
  review_interval_months integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_document_save"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.drive_document_submit (
  node       uuid,
  attachment uuid DEFAULT NULL::uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_document_submit"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.drive_documents (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_documents"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.notify_due_drive_reviews()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notify_due_drive_reviews"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.acknowledge (
  subject_type text,
  subject_id   text,
  version_id   uuid DEFAULT NULL::uuid,
  signature_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_tenant uuid;
  v_version uuid;
  v_row "better_supabase"."acknowledgements"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null then
    raise exception 'sign in to acknowledge' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  select x."tenant_id" into v_tenant
    from "better_supabase"."acknowledgement_assignments" x
    join "public"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select r."key" from "better_supabase"."roles" r where r."id" = m."role"))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
    limit 1;
  if v_tenant is null then
    raise exception 'you aren''t asked to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_NOT_ASSIGNED';
  end if;
  if not (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.acknowledge'), false) and case acknowledge.subject_type
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (acknowledge.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (acknowledge.subject_id)::uuid and s."tenant_id" = v_tenant and (coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end) then
    raise exception 'not allowed to acknowledge this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledge.subject_type, acknowledge.subject_id);
  if v_version is null then
    raise exception 'the record has no version to acknowledge' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_NO_VERSION';
  end if;
  if acknowledge.version_id is not null and acknowledge.version_id <> v_version then
    raise exception 'the record has a newer version; acknowledge that one' using errcode = '55000', hint = 'ACKNOWLEDGEMENT_VERSION_STALE';
  end if;
  if acknowledge.signature_id is not null and not exists (
    select 1 from "better_supabase"."signatures" sg
    join "better_supabase"."signature_requests" sr on sr."id" = sg."request_id"
    where sg."id" = acknowledge.signature_id
      and sg."signer" = v_me
      and sr."status" = 'completed'
      and sr."tenant_id" = v_tenant
      and sr."subject_type" = acknowledge.subject_type
      and sr."subject_id" = acknowledge.subject_id
      and sr."version_id" = v_version
  ) then
    raise exception 'the signature isn''t your completed signature on this version' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_create"(uuid, text, text, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid, $5::uuid)', v_hook::oid::regproc)
        using v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me;
    end if;
  end;
  insert into "better_supabase"."acknowledgements" ("tenant_id", "subject_type", "subject_id", "version_id", "user_id", "method", "signature_id")
  values (v_tenant, acknowledge.subject_type, acknowledge.subject_id, v_version, v_me, case when acknowledge.signature_id is null then 'click' else 'signature' end, acknowledge.signature_id)
  on conflict ("subject_type", "subject_id", "version_id", "user_id") do nothing
  returning * into v_row;
  if found then
    perform "better_supabase".emit_event('acknowledgement.created', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id"), 'acknowledgements/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement.created',
    category => 'data',
    target_type => 'acknowledgement',
    record_id => v_row."id"::text,
    summary => 'acknowledged ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id")
  );
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  else
    select * into v_row from "better_supabase"."acknowledgements" x
    where x."subject_type" = acknowledge.subject_type and x."subject_id" = acknowledge.subject_id
      and x."version_id" = v_version and x."user_id" = v_me;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'userId', v_row."user_id", 'method', v_row."method", 'signatureId', v_row."signature_id", 'acknowledgedAt', v_row."acknowledged_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.acknowledgement_status (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id limit 1)
  );
  v_version uuid;
  v_created timestamptz;
begin
  if v_tenant is null then
    return jsonb_build_object('versionId', null, 'required', 0, 'acknowledged', 0, 'pending', '[]'::jsonb);
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and case acknowledgement_status.subject_type
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (acknowledgement_status.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (acknowledgement_status.subject_id)::uuid and s."tenant_id" = v_tenant and (coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgement_status.subject_type, acknowledgement_status.subject_id);
  select x."created_at" into v_created from "better_supabase"."versions" x where x."id" = v_version;
  return (
    select jsonb_build_object(
      'versionId', v_version,
      'required', count(*),
      'acknowledged', count(k."id"),
      'pending', coalesce(jsonb_agg(jsonb_build_object(
        'userId', c.user_id,
        'dueOn', (v_created)::date + c.due_in_days,
        'overdue', coalesce((v_created)::date + c.due_in_days < current_date, false)
      ) order by (v_created)::date + c.due_in_days nulls last, c.user_id) filter (where k."id" is null), '[]'::jsonb)
    )
    from (select m."user_id" as user_id, min(x."due_in_days") as due_in_days
      from "better_supabase"."acknowledgement_assignments" x
      join "public"."memberships" m on m."organization_id" = x."tenant_id"
      where x."tenant_id" = v_tenant and x."subject_type" = acknowledgement_status.subject_type and x."subject_id" = acknowledgement_status.subject_id
        and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select r."key" from "better_supabase"."roles" r where r."id" = m."role"))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
      group by m."user_id") c
    left join "better_supabase"."acknowledgements" k on k."subject_type" = acknowledgement_status.subject_type and k."subject_id" = acknowledgement_status.subject_id
      and k."version_id" = v_version and k."user_id" = c.user_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.acknowledgements_of (
  subject_type text,
  subject_id   text,
  version_id   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = acknowledgements_of.subject_type and x."subject_id" = acknowledgements_of.subject_id limit 1)
  );
  v_version uuid;
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and case acknowledgements_of.subject_type
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (acknowledgements_of.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (acknowledgements_of.subject_id)::uuid and s."tenant_id" = v_tenant and (coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end)) then
    raise exception 'not allowed to read acknowledgements of this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  v_version := coalesce(acknowledgements_of.version_id, "better_supabase"."current_acknowledgement_version"(v_tenant, acknowledgements_of.subject_type, acknowledgements_of.subject_id));
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'versionId', x."version_id", 'userId', x."user_id", 'method', x."method", 'signatureId', x."signature_id", 'acknowledgedAt', x."acknowledged_at") order by x."acknowledged_at"), '[]'::jsonb)
    from "better_supabase"."acknowledgements" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = acknowledgements_of.subject_type
      and x."subject_id" = acknowledgements_of.subject_id
      and x."version_id" = v_version
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_finalize (
  request_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_run jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_finalize.request_id;
  v_run := v_req."policy" -> 'run';
  if v_req."subject_type" = 'ai_tool_approval' then
    perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", true, (select x."comment" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" order by x."created_at" desc, x."id" desc limit 1));
  end if;
  if v_req."subject_type" = 'access_request' then
    perform "better_supabase"."grant_access_request"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'drive_node' then
    perform "better_supabase"."drive_document_decided"(v_req."id", true);
  end if;
  if v_req."subject_type" = 'timesheet' then
    perform "better_supabase"."approve_timesheet"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'expense_report' then
    perform "better_supabase"."approve_expense_report"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'content_entry' then
    perform "better_supabase"."content_entry_approved"((v_req."subject_id")::uuid);
  end if;
  perform "better_supabase".emit_event('approval.approved', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.approved',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'approved' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  perform "better_supabase"."approval_notify"(v_req."id", 'approved');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_policy (
  subject_type text,
  action       text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(case approval_policy.subject_type || ':' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    when 'customer:discount' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'customer:refund' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'customer:export' then '{"steps":[{"approvers":{"manager":true},"required":1}],"selfApproval":false,"expiresIn":null,"run":null,"mode":"confirm"}'::jsonb
    when 'drive_node:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'drive_node:release' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":2}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'eve_tool_call:add_note' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'workflow_run:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    else null::jsonb
  end, case '*:' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    else null::jsonb
  end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_acknowledgement (
  tenant         uuid,
  subject_type   text,
  subject_id     text,
  principal_type text,
  principal_id   text,
  due_in_days    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
  v_existed boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'acknowledgements.manage'), false) and case assign_acknowledgement.subject_type
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (assign_acknowledgement.subject_id)::uuid and s."tenant_id" = assign_acknowledgement.tenant) and coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (assign_acknowledgement.subject_id)::uuid and s."tenant_id" = assign_acknowledgement.tenant and (coalesce(better_supabase.can('tenant', assign_acknowledgement.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end)) then
    raise exception 'not allowed to assign acknowledgements on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  if assign_acknowledgement.subject_type not in ('policy', 'drive_node') then
    raise exception 'blocks.acknowledgements.on does not allow this record type' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_SUBJECT_UNSUPPORTED';
  end if;
  if assign_acknowledgement.due_in_days is not null and (assign_acknowledgement.due_in_days < 1 or assign_acknowledgement.due_in_days > 365) then
    raise exception 'due_in_days must be between 1 and 365' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_DUE_INVALID';
  end if;
  if assign_acknowledgement.principal_type = 'user' then
    if not exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = assign_acknowledgement.tenant and m."user_id"::text = assign_acknowledgement.principal_id
    ) then
      raise exception 'the user isn''t a member of this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'team' then
    if not exists (
      select 1 from "better_supabase"."teams" t
      where t."id"::text = assign_acknowledgement.principal_id
        and t."tenant_id" = assign_acknowledgement.tenant
    ) then
      raise exception 'the team isn''t a team in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  elsif assign_acknowledgement.principal_type = 'role' then
    if not (assign_acknowledgement.principal_id = any (array['owner', 'admin', 'member', 'viewer']::text[])
      or exists (select 1 from "public"."memberships" m where m."organization_id" = assign_acknowledgement.tenant and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = assign_acknowledgement.principal_id)) then
      raise exception 'the role isn''t a role in this organization' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
    end if;
  else
    raise exception 'principal_type must be user, team or role' using errcode = '22023', hint = 'ACKNOWLEDGEMENT_PRINCIPAL_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_acknowledgement_assignment_create"(uuid, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id;
    end if;
  end;
  select exists (
    select 1 from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = assign_acknowledgement.tenant
      and x."subject_type" = assign_acknowledgement.subject_type
      and x."subject_id" = assign_acknowledgement.subject_id
      and x."principal_type" = assign_acknowledgement.principal_type
      and x."principal_id" = assign_acknowledgement.principal_id
  ) into v_existed;
  insert into "better_supabase"."acknowledgement_assignments" ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id", "due_in_days")
  values (assign_acknowledgement.tenant, assign_acknowledgement.subject_type, assign_acknowledgement.subject_id, assign_acknowledgement.principal_type, assign_acknowledgement.principal_id, assign_acknowledgement.due_in_days)
  on conflict ("tenant_id", "subject_type", "subject_id", "principal_type", "principal_id")
  do update set "due_in_days" = excluded."due_in_days"
  returning * into v_row;
  if not v_existed then
    perform "better_supabase".emit_event('acknowledgement_assignment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id"), 'acknowledgement-assignments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement_assignment.created',
    category => 'data',
    target_type => 'acknowledgement_assignment',
    record_id => v_row."id"::text,
    summary => 'asked ' || v_row."principal_type" || ' ' || v_row."principal_id" || ' to acknowledge ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_acknowledgement_assignment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_transition_drive_node()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    
    
    
    return new;
  end if;
  if new."document_status" is not distinct from old."document_status" then
    return new;
  end if;
  if new."document_status" is null or not (old."document_status" is null and new."document_status"::text = 'draft') and not (case old."document_status"::text when 'draft' then new."document_status"::text = any ('{in_review}'::text[]) when 'in_review' then new."document_status"::text = any ('{draft,effective}'::text[]) when 'effective' then new."document_status"::text = any ('{obsolete}'::text[]) else false end) then
    raise exception 'that status change is not allowed' using errcode = '22023', hint = 'STATE_TRANSITION_INVALID';
  end if;
  -- The approvals module sets better_supabase.approval to the request it
  -- just approved before it makes the transition.
  if (case old."document_status"::text when 'in_review' then new."document_status"::text = any ('{effective}'::text[]) else false end)
    and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    and not exists (
      select 1 from "better_supabase"."approval_requests" a
      where a."id"::text = nullif(current_setting('better_supabase.approval', true), '')
        and a."status" = 'approved'
        and a."subject_type" = 'drive_node'
        and a."subject_id" = new."id"::text
    ) then
    raise exception 'that status change needs an approved request' using errcode = '42501', hint = 'STATE_APPROVAL_REQUIRED';
  end if;
  insert into "better_supabase"."status_history" ("tenant_id", "subject_type", "subject_id", "from_status", "to_status", "actor_user_id", "reason", "actor_name", "actor_email", "ip_address", "user_agent")
        values (new."tenant_id", 'drive_node', new."id"::text, old."document_status"::text, new."document_status"::text, coalesce(auth.uid(), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'id', '')::uuid), nullif(current_setting('better_supabase.transition_reason', true), ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'name', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'email', ''), nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'ip', '')::inet, nullif(nullif(current_setting('better_supabase.transition_actor', true), '')::jsonb ->> 'userAgent', ''));
  
  perform "better_supabase".emit_event('status.changed', jsonb_build_object('organizationId', new."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', new."id"::text, 'from', old."document_status"::text, 'to', new."document_status"::text, 'reason', nullif(current_setting('better_supabase.transition_reason', true), '')), 'statuses/drive_node/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/state-machine');
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.converted_into (
  tenant      uuid,
  origin_type text,
  origin_id   text,
  into_type   text
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select r."source_id"
  from "better_supabase"."relations" r
  where r."tenant_id" = converted_into.tenant
    and r."kind" = (select k.canonical from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('variant_of', 'variant_of', false, true, true, false, 'variants'), ('variants', 'variant_of', true, true, true, false, 'variant_of'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents'), ('mitigated_by', 'mitigated_by', false, false, false, false, 'mitigates'), ('mitigates', 'mitigated_by', true, false, false, false, 'mitigated_by'), ('materialized_as', 'materialized_as', false, false, false, false, 'materializes'), ('materializes', 'materialized_as', true, false, false, false, 'materialized_as')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = 'created_from')
    and r."target_type" = converted_into.origin_type and r."target_id" = converted_into.origin_id
    and r."source_type" = converted_into.into_type
  order by r."created_at", r."id"
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.current_acknowledgement_version (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if current_acknowledgement_version.subject_type = 'policy' then
    return (select s."current_version_id"::uuid from "better_supabase"."policies" s where s."id" = (current_acknowledgement_version.subject_id)::uuid and s."tenant_id" = current_acknowledgement_version.tenant);
  end if;
  if current_acknowledgement_version.subject_type = 'drive_node' then
    return (select s."effective_version_id"::uuid from "better_supabase"."drive_nodes" s where s."id" = (current_acknowledgement_version.subject_id)::uuid and s."tenant_id" = current_acknowledgement_version.tenant);
  end if;
  return (
    select x."id" from "better_supabase"."versions" x
    where x."tenant_id" = current_acknowledgement_version.tenant
      and x."subject_type" = current_acknowledgement_version.subject_type
      and x."subject_id" = current_acknowledgement_version.subject_id
      and x."frozen"
    order by x."number" desc
    limit 1
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_approval (
  request_id uuid,
  decision   text,
  comment    text DEFAULT NULL::text,
  decided_by uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_count integer;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_actor uuid := coalesce(decide_approval.decided_by, auth.uid());
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if decide_approval.decision not in ('approved', 'rejected') then
    raise exception 'decision must be approved or rejected' using errcode = '22023', hint = 'APPROVAL_DECISION_INVALID';
  end if;
  if decide_approval.decided_by is not null and not v_service and decide_approval.decided_by is distinct from auth.uid() then
    raise exception 'only the service role decides for another user' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = decide_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  if v_req."expires_at" is not null and v_req."expires_at" <= now() then
    raise exception 'this request has expired' using errcode = '22023', hint = 'APPROVAL_EXPIRED';
  end if;
  if v_service then
    if v_actor is not null and v_actor = v_req."requested_by" and coalesce(v_req."policy" ->> 'mode', 'authorize') <> 'confirm'
      and not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      raise exception 'the requester can''t decide their own request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
    if v_actor is not null and exists (
      select 1 from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = v_actor
    ) then
      raise exception 'this user already decided this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
  elsif not "better_supabase"."approval_eligible"(v_req."id") then
    raise exception 'not an approver for this step' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", decide_approval.decision;
    end if;
  end;
  insert into "better_supabase"."approval_decisions" ("request_id", "tenant_id", "step", "approver", "decision", "comment")
  values (v_req."id", v_req."tenant_id", v_req."step", v_actor, decide_approval.decision, decide_approval.comment);
  if decide_approval.decision = 'rejected' then
    update "better_supabase"."approval_requests" r set "status" = 'rejected', "decided_at" = now()
      where r."id" = v_req."id" returning * into v_req;
    perform "better_supabase".emit_event('approval.rejected', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.rejected',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'rejected' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
    perform "better_supabase"."approval_notify"(v_req."id", 'rejected');
    if v_req."subject_type" = 'ai_tool_approval' then
      perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", false, decide_approval.comment);
    end if;
    if v_req."subject_type" = 'drive_node' then
      perform "better_supabase"."drive_document_decided"(v_req."id", false);
    end if;
  else
    select count(*) into v_count from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved';
    if v_req."policy" ->> 'mode' = 'confirm' and v_req."requested_by" = v_actor then
      update "better_supabase"."approval_requests" r set "status" = 'approved', "decided_at" = now()
        where r."id" = v_req."id" returning * into v_req;
      perform "better_supabase"."approval_finalize"(v_req."id");
    elsif v_count >= coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'required')::integer, 1) then
      if v_req."step" + 1 >= jsonb_array_length(v_req."policy" -> 'steps') then
        update "better_supabase"."approval_requests" r set "status" = 'approved', "decided_at" = now()
          where r."id" = v_req."id" returning * into v_req;
        perform "better_supabase"."approval_finalize"(v_req."id");
      else
        update "better_supabase"."approval_requests" r set "step" = r."step" + 1, "reminded_at" = null
          where r."id" = v_req."id" returning * into v_req;
        perform "better_supabase"."approval_notify"(v_req."id", 'requested');
      end if;
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_approval_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_req."id", v_req."status";
    end if;
  end;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_decided (
  request  uuid,
  approved boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" q where q."id" = drive_document_decided.request;
  if not found or v_req."action" <> 'release' or v_req."subject_type" <> 'drive_node' then
    return;
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id"::text = v_req."subject_id" for update;
  if not found or v_node."document_status" is null or v_node."document_status" not in ('in_review', 'effective') then
    return;
  end if;
  if drive_document_decided.approved then
    perform set_config('better_supabase.approval', v_req."id"::text, true);
    perform "better_supabase"."drive_document_release"(v_node."id", coalesce((v_req."payload" ->> 'attachmentId')::uuid, v_node."attachment_id"));
    perform set_config('better_supabase.approval', '', true);
  elsif v_node."document_status" = 'in_review' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', 'rejected');
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_obsolete (
  node   uuid,
  reason text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_obsolete.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be obsoleted' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'owner')) then
    raise exception 'not allowed to withdraw this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document can be made obsolete' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'obsolete', drive_document_obsolete.reason);
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive.node_obsoleted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive.node_obsoleted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document made obsolete',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'reason', drive_document_obsolete.reason)
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_readable (
  node       uuid,
  attachment uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce((
    select x."document_status" is null or "better_supabase"."drive_can"(x."id", 'editor')
      or coalesce(drive_document_readable.attachment = (select (r."content" ->> 'attachmentId')::uuid from "better_supabase"."versions" r where r."id" = x."effective_version_id"), false)
    from "better_supabase"."drive_nodes" x where x."id" = drive_document_readable.node
  ), true)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_release (
  node       uuid,
  attachment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_version uuid;
  v_inserted jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."id"::text = nullif(current_setting('better_supabase.approval', true), '')
      and q."status" = 'approved' and q."action" = 'release'
      and q."subject_type" = 'drive_node' and q."subject_id" = drive_document_release.node::text
  )) then
    raise exception 'only an approved release request releases a document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_release.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if v_node."document_status" is null or v_node."document_status" not in ('in_review', 'effective') then
    raise exception 'only a document in review or an effective one can be released' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = drive_document_release.attachment
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."id" into v_version from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" desc limit 1;
  if v_version is null then
    v_inserted := "better_supabase"."version_insert"(v_node."tenant_id", 'drive_node', v_node."id"::text,
      jsonb_build_object('attachmentId', v_file."id", 'name', v_file."name", 'mimeType', v_file."mime_type", 'size', v_file."size"),
      v_file."bucket" || '/' || v_file."object_path", 'effective', 'manual', true, auth.uid());
    v_version := (v_inserted ->> 'id')::uuid;
  else
    update "better_supabase"."versions" r set "label" = 'effective', "frozen" = true where r."id" = v_version;
  end if;
  update "better_supabase"."versions" r set "label" = 'superseded'
  where r."id" = v_node."effective_version_id" and r."id" <> v_version;
  update "better_supabase"."drive_nodes" x set "effective_version_id" = v_version, "effective_from" = now(),
    "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
  where x."id" = v_node."id";
  if v_node."document_status" = 'in_review' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'effective', 'released');
  end if;
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive.node_released', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive.node_released',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document released',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'versionId', v_version, 'attachmentId', v_file."id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_review (
  node    uuid,
  outcome text,
  note    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_review.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be reviewed' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_node."document_owner_id" = auth.uid() or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to review this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if drive_document_review.outcome is null or drive_document_review.outcome not in ('unchanged', 'revise') then
    raise exception 'outcome must be unchanged or revise' using errcode = '22023', hint = 'DRIVE_DOCUMENT_REVIEW_INVALID';
  end if;
  if v_node."document_status" is distinct from 'effective' then
    raise exception 'only an effective document is reviewed' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_review.outcome = 'unchanged' then
    update "better_supabase"."drive_nodes" x set "next_review_on" = (current_date + make_interval(months => coalesce(v_node."review_interval_months", 12)))::date, "review_notified_for" = null
    where x."id" = v_node."id"
    returning * into v_node;
  end if;
  perform "better_supabase".emit_event('drive.node_reviewed', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive.node_reviewed',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document reviewed',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'outcome', drive_document_review.outcome, 'note', drive_document_review.note, 'nextReviewOn', v_node."next_review_on")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_save (
  node                   uuid,
  document_type          text,
  owner_id               uuid    DEFAULT NULL::uuid,
  review_interval_months integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_seq bigint;
  v_number text;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_save.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be a controlled document' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to control this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (array['sop', 'policy', 'form']::text[])) then
    raise exception 'that document type is not in options.control.types' using errcode = '22023', hint = 'DRIVE_DOCUMENT_TYPE_UNKNOWN';
  end if;
  if v_node."document_status" = 'obsolete' then
    raise exception 'an obsolete document can''t change' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_document_save.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'DRIVE_DOCUMENT_OWNER_INVALID';
  end if;
  v_number := v_node."document_number";
  if v_number is null then
    v_seq := "better_supabase"."next_number"(v_node."tenant_id", 'drive_document', now());
    v_number := better_supabase.format_assigned_number('DOC-{n:5}', v_seq, now());
  end if;
  update "better_supabase"."drive_nodes" x set "document_number" = v_number,
    "document_type" = drive_document_save.document_type,
    "document_owner_id" = coalesce(drive_document_save.owner_id, x."document_owner_id", auth.uid()),
    "review_interval_months" = coalesce(drive_document_save.review_interval_months, x."review_interval_months"), "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  if v_node."document_status" is null then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', null);
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  end if;
  perform "better_supabase".emit_event('drive.node_document_saved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive.node_document_saved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document saved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_submit (
  node       uuid,
  attachment uuid DEFAULT NULL::uuid,
  reason     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_file "better_supabase"."attachments"%rowtype;
  v_revision integer;
  v_request jsonb;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_submit.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be released' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to submit this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if v_node."document_status" is null then
    raise exception 'save the file as a controlled document first' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if not (v_node."document_status" = 'draft' or (v_node."document_status" in ('in_review', 'effective') and not exists (
    select 1 from "better_supabase"."approval_requests" q
    where q."subject_type" = 'drive_node' and q."subject_id" = v_node."id"::text
      and q."action" = 'release' and q."status" = 'pending'
  ))) then
    raise exception 'only a draft, or an effective document without a pending release, can be submitted' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  select * into v_file from "better_supabase"."attachments" f
  where f."id" = coalesce(drive_document_submit.attachment, v_node."attachment_id")
    and f."subject_type" = 'drive_node' and f."subject_id" = v_node."id"::text
    and f."uploaded_at" is not null;
  if not found then
    raise exception 'that version of the file was not found' using errcode = 'P0002', hint = 'DRIVE_ATTACHMENT_NOT_FOUND';
  end if;
  select r."number" into v_revision from "better_supabase"."versions" r
  where r."subject_type" = 'drive_node' and r."subject_id" = v_node."id"::text
    and r."content" ->> 'attachmentId' = v_file."id"::text
  order by r."number" limit 1;
  if v_node."document_status" = 'draft' then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'in_review', drive_document_submit.reason);
  end if;
  v_request := "better_supabase"."request_approval"(v_node."tenant_id", 'drive_node', v_node."id"::text, 'release',
    drive_document_submit.reason, jsonb_build_object('attachmentId', v_file."id", 'revision', v_revision, 'name', v_file."name"));
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  perform "better_supabase".emit_event('drive.node_submitted', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id'), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive.node_submitted',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document submitted',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'attachmentId', v_file."id", 'requestId', v_request ->> 'id')
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_documents (
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
begin
  if jsonb_typeof(coalesce(drive_documents.filters, '{}'::jsonb)) <> 'object' then
    raise exception 'filters must be an object' using errcode = '22023', hint = 'DRIVE_DOCUMENT_FILTER_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(("better_supabase"."drive_node_json"(x) || jsonb_build_object('role', "better_supabase"."drive_role"((x)."id"), 'readOnly', (coalesce((x)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((x)."id"), 'downloadable', "better_supabase"."drive_can_download"((x)."id"))) order by x."document_number")
    from "better_supabase"."drive_nodes" x
    where x."tenant_id" = drive_documents.tenant and x."document_status" is not null and x."deleted_at" is null
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(x."id", 'viewer'))
      and (drive_documents.filters ->> 'type' is null or x."document_type" = drive_documents.filters ->> 'type')
      and (drive_documents.filters ->> 'status' is null or x."document_status" = drive_documents.filters ->> 'status')
      and (drive_documents.filters ->> 'ownerId' is null or x."document_owner_id"::text = drive_documents.filters ->> 'ownerId')
      and (coalesce((drive_documents.filters ->> 'reviewDue')::boolean, false) = false
        or (x."document_status" = 'effective' and x."next_review_on" <= current_date))
      and (coalesce(drive_documents.filters ->> 'search', '') = ''
        or x."document_number" ilike '%' || (drive_documents.filters ->> 'search') || '%'
        or x."name" ilike '%' || (drive_documents.filters ->> 'search') || '%')
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_json (
  node better_supabase.drive_nodes
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', ($1)."id", 'organizationId', ($1)."tenant_id", 'driveId', null, 'parentId', ($1)."parent_id", 'kind', ($1)."kind", 'name', ($1)."name", 'rank', ($1)."rank", 'source', ($1)."source", 'externalId', ($1)."external_id", 'externalMetadata', ($1)."external_metadata", 'legalHoldUntil', ($1)."legal_hold_until", 'lockedBy', case when ($1)."locked_until" > now() then ($1)."locked_by" end, 'lockedUntil', case when ($1)."locked_until" > now() then ($1)."locked_until" end, 'lockNote', case when ($1)."locked_until" > now() then ($1)."lock_note" end, 'downloadBlocked', ($1)."download_blocked", 'previewPages', ($1)."preview_pages", 'createdBy', ($1)."created_by", 'createdAt', ($1)."created_at", 'updatedAt', ($1)."updated_at", 'deletedAt', ($1)."deleted_at", 'attachmentId', ($1)."attachment_id", 'file', (select jsonb_build_object('mimeType', fa."mime_type", 'size', fa."size", 'status', fa."status", 'uploadedAt', fa."uploaded_at") from "better_supabase"."attachments" fa where fa."id" = ($1)."attachment_id"), 'labels', (select coalesce(jsonb_agg(jsonb_build_object('id', lt."id", 'name', lt."name", 'color', lt."color") order by lt."rank" collate "C", lt."name", lt."id"), '[]'::jsonb)
      from "better_supabase"."taggings" lg join "better_supabase"."tags" lt on lt."id" = lg."tag_id"
      where lg."subject_type" = 'drive_node' and lg."subject_id" = ($1)."id"::text), 'approval', (select jsonb_build_object('id', lr."id", 'status', lr."status", 'createdAt', lr."created_at", 'decidedAt', lr."decided_at")
      from "better_supabase"."approval_requests" lr
      where lr."subject_type" = 'drive_node' and lr."subject_id" = ($1)."id"::text and lr."action" = 'approve'
        and lr."payload" ->> 'attachmentId' = ($1)."attachment_id"::text
      order by lr."created_at" desc, lr."id" limit 1), 'document', case when ($1)."document_status" is null then null else jsonb_build_object('number', ($1)."document_number", 'type', ($1)."document_type", 'status', ($1)."document_status", 'ownerId', ($1)."document_owner_id", 'effectiveVersionId', ($1)."effective_version_id", 'effectiveVersion', (select r."number" from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveAttachmentId', (select (r."content" ->> 'attachmentId')::uuid from "better_supabase"."versions" r where r."id" = ($1)."effective_version_id"), 'effectiveFrom', ($1)."effective_from", 'reviewIntervalMonths', ($1)."review_interval_months", 'nextReviewOn', ($1)."next_review_on", 'reviewDue', coalesce(($1)."document_status" = 'effective' and ($1)."next_review_on" <= current_date, false), 'effectiveOnly', not "better_supabase"."drive_can"(($1)."id", 'editor')) end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_object_allowed (
  bucket text,
  path   text,
  action text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case when drive_object_allowed.path like '_previews/%' then
    drive_object_allowed.action = 'select'
      and split_part(drive_object_allowed.path, '/', 3) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and "better_supabase"."drive_can"(split_part(drive_object_allowed.path, '/', 3)::uuid, 'viewer') and "better_supabase"."drive_document_readable"(split_part(drive_object_allowed.path, '/', 3)::uuid, (select pn."attachment_id" from "better_supabase"."drive_nodes" pn where pn."id"::text = split_part(drive_object_allowed.path, '/', 3)))
  else coalesce((
    select case
      when f."subject_type" is distinct from 'drive_node' then true
      when f."subject_id" !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then false
      when drive_object_allowed.action = 'select' then "better_supabase"."drive_can_download"(f."subject_id"::uuid) and "better_supabase"."drive_document_readable"(f."subject_id"::uuid, f."id")
      else "better_supabase"."drive_node_writable"(f."subject_id"::uuid) or "better_supabase"."drive_uploaded_own"(f."subject_id"::uuid)
    end
    from "better_supabase"."attachments" f
    where f."bucket" = drive_object_allowed.bucket and f."object_path" = drive_object_allowed.path
  ), true) end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text,
  data        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_id uuid;
  v_created boolean := false;
  v_previous jsonb;
  v_replaced jsonb;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', link.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to link records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;
  if link.data is not null and jsonb_typeof(link.data) <> 'object' then
    raise exception 'data must be an object' using errcode = '22023', hint = 'RELATION_INVALID';
  end if;
  if link.source_type = link.target_type and link.source_id = link.target_id then
    raise exception 'a record can''t link to itself' using errcode = '22023', hint = 'RELATION_SELF';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('variant_of', 'variant_of', false, true, true, false, 'variants'), ('variants', 'variant_of', true, true, true, false, 'variant_of'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents'), ('mitigated_by', 'mitigated_by', false, false, false, false, 'mitigates'), ('mitigates', 'mitigated_by', true, false, false, false, 'mitigated_by'), ('materialized_as', 'materialized_as', false, false, false, false, 'materializes'), ('materializes', 'materialized_as', true, false, false, false, 'materialized_as')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = link.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := link.target_type; v_source_id := link.target_id;
    v_target_type := link.source_type; v_target_id := link.source_id;
  else
    v_source_type := link.source_type; v_source_id := link.source_id;
    v_target_type := link.target_type; v_target_id := link.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if v_kind = 'variant_of' and not (v_source_type in ('drive_node') and v_target_type in ('drive_node')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if v_kind = 'represents' and not (v_source_type in ('person') and v_target_type in ('customer')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if v_kind = 'mitigated_by' and not (v_source_type in ('risk') and v_target_type in ('control', 'work_item', 'drive_node')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if v_kind = 'materialized_as' and not (v_source_type in ('risk') and v_target_type in ('case')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if not (case link.source_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'risks.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant and (coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    else false
  end)
     or not (case link.target_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'risks.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant and (coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    else false
  end) then
    raise exception 'not allowed to link these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_relation_link"(uuid, text, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text, $6::text)', v_hook::oid::regproc)
        using link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id;
    end if;
  end;
  if v_acyclic or v_single then
    perform pg_advisory_xact_lock(hashtext(link.tenant::text || ':relation:' || v_kind));
  end if;
  select "id", "data" into v_id, v_previous from "better_supabase"."relations"
    where "tenant_id" = link.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id;
  if v_id is null then
    if v_kind = 'represents' and not coalesce((jsonb_typeof(coalesce(link.data, '{}'::jsonb)) = 'object'
      and (coalesce(link.data, '{}'::jsonb) ->> 'role') in ('legal_representative', 'guardian', 'mentor', 'curator', 'parent', 'contact_person', 'emergency_contact', 'other')
      and (coalesce(link.data, '{}'::jsonb) ->> 'authority') in ('inform', 'act')
      and (coalesce(link.data, '{}'::jsonb) -> 'valid_from' is null or (jsonb_typeof(coalesce(link.data, '{}'::jsonb) -> 'valid_from') = 'string' and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_from', 'date')))
      and (coalesce(link.data, '{}'::jsonb) -> 'valid_until' is null or (jsonb_typeof(coalesce(link.data, '{}'::jsonb) -> 'valid_until') = 'string' and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_until', 'date')))
      and case when pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_from', 'date') and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_until', 'date')
        then (coalesce(link.data, '{}'::jsonb) ->> 'valid_from')::date <= (coalesce(link.data, '{}'::jsonb) ->> 'valid_until')::date else true end), false) then
      raise exception 'this kind of link doesn''t accept this data' using errcode = '22023', hint = 'RELATION_DATA_INVALID';
    end if;
    if v_acyclic and exists (
      with recursive reach(t, i, depth) as (
        select v_target_type, v_target_id, 0
        union
        select r."target_type", r."target_id", reach.depth + 1
        from "better_supabase"."relations" r join reach
          on r."source_type" = reach.t and r."source_id" = reach.i
        where r."tenant_id" = link.tenant and r."kind" = v_kind and reach.depth < 1000
      )
      select 1 from reach where t = v_source_type and i = v_source_id
    ) then
      raise exception 'this link would create a cycle' using errcode = '23514', hint = 'RELATION_CYCLE';
    end if;
    if v_single then
      delete from "better_supabase"."relations"
        where "tenant_id" = link.tenant and "kind" = v_kind
          and "source_type" = v_source_type and "source_id" = v_source_id
        returning * into v_old;
      if v_old."id" is not null then
        v_replaced := jsonb_build_object('targetType', v_old."target_type", 'targetId', v_old."target_id", 'data', v_old."data");
        perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', link.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_old."target_type", 'targetId', v_old."target_id"), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
      end if;
    end if;
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "data", "created_by")
    values (link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id, coalesce(link.data, '{}'::jsonb), auth.uid())
    returning "id" into v_id;
    v_created := true;
    perform "better_supabase".emit_event('subject.linked', jsonb_build_object('organizationId', link.tenant, 'id', v_id, 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
  elsif link.data is not null then
    if v_kind = 'represents' and not coalesce((jsonb_typeof(link.data) = 'object'
      and (link.data ->> 'role') in ('legal_representative', 'guardian', 'mentor', 'curator', 'parent', 'contact_person', 'emergency_contact', 'other')
      and (link.data ->> 'authority') in ('inform', 'act')
      and (link.data -> 'valid_from' is null or (jsonb_typeof(link.data -> 'valid_from') = 'string' and pg_input_is_valid(link.data ->> 'valid_from', 'date')))
      and (link.data -> 'valid_until' is null or (jsonb_typeof(link.data -> 'valid_until') = 'string' and pg_input_is_valid(link.data ->> 'valid_until', 'date')))
      and case when pg_input_is_valid(link.data ->> 'valid_from', 'date') and pg_input_is_valid(link.data ->> 'valid_until', 'date')
        then (link.data ->> 'valid_from')::date <= (link.data ->> 'valid_until')::date else true end), false) then
      raise exception 'this kind of link doesn''t accept this data' using errcode = '22023', hint = 'RELATION_DATA_INVALID';
    end if;
    update "better_supabase"."relations" set "data" = link.data where "id" = v_id;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_relation_link"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object(
    'id', v_id, 'kind', v_kind, 'created', v_created,
    'sourceType', v_source_type, 'sourceId', v_source_id,
    'targetType', v_target_type, 'targetId', v_target_id,
    'previousData', case when v_created then null else v_previous end,
    'replaced', v_replaced);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_acknowledgement_assignments (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := coalesce(
    (select x."tenant_id" from "better_supabase"."acknowledgement_assignments" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."acknowledgements" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1),
    (select x."tenant_id" from "better_supabase"."versions" x where x."subject_type" = list_acknowledgement_assignments.subject_type and x."subject_id" = list_acknowledgement_assignments.subject_id limit 1)
  );
begin
  if v_tenant is null then
    return '[]'::jsonb;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_tenant, 'acknowledgements.read'), false) and case list_acknowledgement_assignments.subject_type
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (list_acknowledgement_assignments.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (list_acknowledgement_assignments.subject_id)::uuid and s."tenant_id" = v_tenant and (coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end)) then
    raise exception 'not allowed to read acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'principalType', x."principal_type", 'principalId', x."principal_id", 'dueInDays', x."due_in_days", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."principal_type", x."principal_id"), '[]'::jsonb)
    from "better_supabase"."acknowledgement_assignments" x
    where x."tenant_id" = v_tenant
      and x."subject_type" = list_acknowledgement_assignments.subject_type
      and x."subject_id" = list_acknowledgement_assignments.subject_id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_activity (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50,
  sources      text[]                   DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := least(greatest(coalesce(list_activity.max_rows, 50), 1), 500);
  v_rows jsonb;
  v_table text;
begin
  if list_activity.subject_id is not null and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
    and not "better_supabase"."activity_subject_readable"(list_activity.subject_type, list_activity.subject_id) then
    return '[]'::jsonb;
  end if;
  if list_activity.subject_id is not null then
    v_table := case list_activity.subject_type
      when 'message' then 'better_supabase.messages'
      when 'conversation' then 'better_supabase.conversations'
      when 'channel' then 'better_supabase.channels'
      when 'company' then 'better_supabase.companies'
      when 'person' then 'better_supabase.people'
      when 'deal' then 'better_supabase.deals'
      when 'course' then 'better_supabase.courses'
      when 'post' then 'better_supabase.posts'
      when 'engagement' then 'better_supabase.engagements'
      when 'quote' then 'better_supabase.quotes'
      when 'work_item' then 'better_supabase.work_items'
      when 'employee' then 'better_supabase.employees'
      when 'invoice' then 'better_supabase.invoices'
      when 'ledger_account' then 'better_supabase.ledger_accounts'
      when 'product' then 'better_supabase.products'
      when 'product_variant' then 'better_supabase.product_variants'
      when 'order' then 'better_supabase.orders'
      when 'calendar_event' then 'better_supabase.calendar_events'
      when 'booking' then 'better_supabase.bookings'
      when 'asset' then 'better_supabase.assets'
      when 'asset_location' then 'better_supabase.asset_locations'
      when 'lease' then 'better_supabase.lease_agreements'
      when 'expense_report' then 'better_supabase.expense_reports'
      when 'expense_line' then 'better_supabase.expense_lines'
      when 'donation_fund' then 'better_supabase.donation_funds'
      when 'work_order' then 'better_supabase.work_orders'
      when 'shipment' then 'better_supabase.shipments'
      when 'contract' then 'better_supabase.contracts'
      when 'control' then 'better_supabase.controls'
      when 'policy' then 'better_supabase.policies'
      when 'qualification_type' then 'better_supabase.qualification_types'
      when 'risk' then 'better_supabase.risks'
      when 'incident' then 'better_supabase.incidents'
      when 'content_entry' then 'better_supabase.content_entries'
      when 'form' then 'better_supabase.forms'
      when 'document' then 'better_supabase.documents'
      when 'customer' then 'public.customers'
      when 'drive_node' then 'better_supabase.drive_nodes'
      when 'application' then 'better_supabase.applications'
      when 'change_request' then 'public.change_requests'
      when 'project' then 'public.projects'
      when 'task' then 'public.tasks'
    end;
  end if;
  select coalesce(jsonb_agg(x.entry order by x.at desc, x.id desc), '[]'::jsonb)
  into v_rows
  from (
    select u.entry, u.at, u.id from (
    (select to_jsonb(y.*) || jsonb_build_object('source', 'event') as entry,
      y."occurred_at" as at, y."id"::text as id
    from "better_supabase"."activity_entries" y
    where y."organization_id" = list_activity.tenant
      and (list_activity.sources is null or 'event' = any (list_activity.sources))
      and (list_activity.subject_type is null or y."subject_type" = list_activity.subject_type)
      and (list_activity.subject_id is null or y."subject_id" = list_activity.subject_id)
      and (list_activity.before is null or y."occurred_at" < list_activity.before)
      and not ((y."type" = 'status.changed' and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources)))
        or (y."type" in ('message.sent', 'comment.posted') and list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))))
    order by y."occurred_at" desc, y."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', l."id"::text, 'organization_id', l."organization_id", 'event_id', null::text, 'type', coalesce(l."event_type", 'audit.' || l."op"), 'actor_id', l."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', l."summary", 'data', jsonb_strip_nulls(jsonb_build_object('op', l."op", 'changed', to_jsonb(l."changed"), 'table', l."table_name")), 'occurred_at', l."occurred_at", 'source', 'audit') as entry,
      l."occurred_at" as at, l."id"::text as id
    from "better_supabase"."audit_events" l
    where v_table is not null
      and (list_activity.sources is null or 'audit' = any (list_activity.sources))
      and l."table_name" = v_table
      and l."record_id" = list_activity.subject_id
      and l."organization_id" = list_activity.tenant
      and (list_activity.before is null or l."occurred_at" < list_activity.before)
    order by l."occurred_at" desc, l."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', r."id"::text, 'organization_id', r."tenant_id", 'event_id', null::text, 'type', 'run.' || r."status", 'actor_id', r."actor_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('runId', r."id", 'definition', r."definition", 'engine', r."engine", 'status', r."status", 'mode', r."mode", 'error', r."error"::text, 'completedAt', r."completed_at")), 'occurred_at', r."created_at", 'source', 'run') as entry,
      r."created_at" as at, r."id"::text as id
    from "better_supabase"."workflow_runs" r
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'run' = any (list_activity.sources))
      and r."tenant_id" = list_activity.tenant
      and r."subject_type" = list_activity.subject_type
      and r."subject_id" = list_activity.subject_id
      and (list_activity.before is null or r."created_at" < list_activity.before)
    order by r."created_at" desc, r."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', h."id"::text, 'organization_id', h."tenant_id", 'event_id', null::text, 'type', 'status.changed', 'actor_id', h."actor_user_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', null::text, 'data', jsonb_strip_nulls(jsonb_build_object('from', h."from_status"::text, 'to', h."to_status"::text, 'reason', h."reason")), 'occurred_at', h."created_at", 'source', 'transition') as entry,
      h."created_at" as at, h."id"::text as id
    from "better_supabase"."status_history" h
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and list_activity.subject_type = any ('{work_item,change_request,drive_node}'::text[])
      and (list_activity.sources is null or 'transition' = any (list_activity.sources))
      and h."tenant_id" = list_activity.tenant
      and h."subject_type" = list_activity.subject_type
      and h."subject_id" = list_activity.subject_id
      and (list_activity.before is null or h."created_at" < list_activity.before)
    order by h."created_at" desc, h."id" desc
    limit v_limit)
    union all
    (select jsonb_build_object('id', m."id"::text, 'organization_id', m."tenant_id", 'event_id', null::text, 'type', case when c."kind" = 'subject' then 'comment.posted' else 'message.sent' end, 'actor_id', m."author_id", 'subject_type', list_activity.subject_type, 'subject_id', list_activity.subject_id, 'summary', left(m."body", 280), 'data', jsonb_strip_nulls(jsonb_build_object('messageId', m."id", 'conversationId', m."conversation_id", 'threadId', m."thread_id", 'kind', m."kind"::text)), 'occurred_at', m."sent_at", 'source', 'message') as entry,
      m."sent_at" as at, m."id"::text as id
    from "better_supabase"."messages" m
    join "better_supabase"."conversations" c on c."id" = m."conversation_id"
    where list_activity.subject_id is not null
      and list_activity.subject_type = any ('{message,conversation,channel,company,person,deal,course,post,engagement,quote,work_item,employee,invoice,ledger_account,product,product_variant,order,calendar_event,booking,asset,asset_location,lease,expense_report,expense_line,donation_fund,work_order,shipment,contract,control,policy,qualification_type,risk,incident,content_entry,form,document,customer,drive_node,application,change_request,project,task}'::text[])
      and (list_activity.sources is null or 'message' = any (list_activity.sources))
      and c."tenant_id" = list_activity.tenant
      and c."subject_type" = list_activity.subject_type
      and c."subject_id" = list_activity.subject_id
      and m."sent_at" is not null
      and m."deleted_at" is null
      and (list_activity.before is null or m."sent_at" < list_activity.before)
    order by m."sent_at" desc, m."id" desc
    limit v_limit)
    union all
    (select d.entry, d.at, d.id
    from "better_supabase"."activity_subject_deliveries"(list_activity.tenant, list_activity.subject_type, list_activity.subject_id, list_activity.before, v_limit) d
    where list_activity.subject_id is not null
      and (list_activity.sources is null or 'delivery' = any (list_activity.sources)))
    ) u
    order by u.at desc, u.id desc
    limit v_limit
  ) x;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_acknowledgements (
  tenant       uuid,
  pending_only boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null or not exists (
    select 1 from "public"."memberships" m where m."organization_id" = list_my_acknowledgements.tenant and m."user_id" = v_me
  ) then
    raise exception 'not a member of this organization' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'organizationId', list_my_acknowledgements.tenant,
      'subjectType', z.subject_type,
      'subjectId', z.subject_id,
      'subjectTitle', "better_supabase"."subject_title"(z.subject_type, z.subject_id),
      'versionId', z.version_id,
      'dueOn', z.due_on,
      'overdue', k."id" is null and z.due_on is not null and z.due_on < current_date,
      'acknowledgedAt', k."acknowledged_at"
    ) order by k."id" is not null, z.due_on nulls last, z.subject_type, z.subject_id), '[]'::jsonb)
    from (
      select y.subject_type, y.subject_id, y.version_id,
        ((select vv."created_at" from "better_supabase"."versions" vv where vv."id" = y.version_id))::date + y.due_in_days as due_on
      from (
        select q.subject_type, q.subject_id, q.due_in_days,
          "better_supabase"."current_acknowledgement_version"(list_my_acknowledgements.tenant, q.subject_type, q.subject_id) as version_id
        from (
          select x."subject_type" as subject_type, x."subject_id" as subject_id, min(x."due_in_days") as due_in_days
          from "better_supabase"."acknowledgement_assignments" x
          join "public"."memberships" m on m."organization_id" = x."tenant_id" and m."user_id" = v_me
          where x."tenant_id" = list_my_acknowledgements.tenant and ((x."principal_type" = 'user' and x."principal_id" = m."user_id"::text)
      or (x."principal_type" = 'role' and x."principal_id" = (select r."key" from "better_supabase"."roles" r where r."id" = m."role"))
      or (x."principal_type" = 'team' and exists (
        select 1 from "better_supabase"."team_members" tm
        where tm."tenant_id" = m."organization_id"
          and tm."user_id" = m."user_id"
          and tm."team_id"::text = x."principal_id"
      )))
          group by x."subject_type", x."subject_id"
        ) q
        where case q.subject_type
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (q.subject_id)::uuid and s."tenant_id" = list_my_acknowledgements.tenant) and coalesce(better_supabase.can('tenant', list_my_acknowledgements.tenant, 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (q.subject_id)::uuid and s."tenant_id" = list_my_acknowledgements.tenant and (coalesce(better_supabase.can('tenant', list_my_acknowledgements.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end
      ) y
      where y.version_id is not null
    ) z
    left join "better_supabase"."acknowledgements" k on k."subject_type" = z.subject_type and k."subject_id" = z.subject_id
      and k."version_id" = z.version_id and k."user_id" = v_me
    where not coalesce(list_my_acknowledgements.pending_only, true) or k."id" is null
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_status_history (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows     integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case list_status_history.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'work_item'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    when 'change_request' then
      if not exists (select 1 from "public"."change_requests" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'change_request'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    when 'drive_node' then
      if not exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (list_status_history.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return coalesce((
        select jsonb_agg(jsonb_build_object('id', r.id, 'from', r.from_status, 'to', r.to_status,
          'actorId', r.actor, 'actorName', r."actorName", 'actorEmail', r."actorEmail", 'ip', r.ip, 'userAgent', r."userAgent",
          'reason', r.reason, 'createdAt', r.created_at) order by r.created_at desc, r.id desc)
        from (select h."id"::text as id, h."from_status" as from_status, h."to_status" as to_status,
          h."actor_user_id"::text as actor, h."actor_name"::text as "actorName", h."actor_email"::text as "actorEmail", regexp_replace(h."ip_address"::text, '/(32|128)$', '') as "ip", h."user_agent"::text as "userAgent", h."reason" as reason, h."created_at" as created_at
        from "better_supabase"."status_history" h
        where h."subject_type" = 'drive_node'
          and h."subject_id" = list_status_history.subject_id
          and (list_status_history.before is null or h."created_at" < list_status_history.before)
        order by h."created_at" desc, h."id" desc
        limit least(greatest(coalesce(list_status_history.max_rows, 50), 1), 500)) r
      ), '[]'::jsonb);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_status_stages (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case list_status_stages.subject_type
    when 'work_item' then
      if not exists (select 1 from "better_supabase"."work_items" s where s."id" = (list_status_stages.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return '[]'::jsonb;
    when 'change_request' then
      if not exists (select 1 from "public"."change_requests" s where s."id" = (list_status_stages.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return '[]'::jsonb;
    when 'drive_node' then
      if not exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (list_status_stages.subject_id)::uuid) then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      return '[]'::jsonb;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.next_number (
  tenant   uuid,
  p_entity text,
  at       timestamp with time zone DEFAULT now()
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := case p_entity
    when 'drive_document' then ''
    when 'donation_receipt' then ''
    when 'risk' then ''
    else null
  end;
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "period", "last_number")
  values (next_number.tenant, p_entity, v_period, 1)
  on conflict ("tenant_id", "entity", "period")
  do update set "last_number" = "better_supabase"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  perform "better_supabase".emit_event('number.assigned', jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n), 'number-sequences/' || p_entity, (next_number.tenant)::text, null, 'better-supabase/numbering');
  perform better_supabase.audit_event(
    event_type => 'number.assigned',
    category => 'data',
    target_type => 'number_sequence',
    record_id => p_entity,
    summary => 'assigned ' || v_n::text,
    tenant => (next_number.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_due_drive_reviews()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  for v_node in
    select * from "better_supabase"."drive_nodes" x
    where x."document_status" = 'effective' and x."next_review_on" <= current_date
      and x."review_notified_for" is distinct from x."next_review_on" and x."deleted_at" is null
    for update skip locked
  loop
    perform "better_supabase".emit_event('drive.node_review_requested', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'ownerId', v_node."document_owner_id", 'nextReviewOn', v_node."next_review_on"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
    if v_node."document_owner_id" is not null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'drive.document_review_due',
        'tenant', v_node."tenant_id",
        'actor', null,
        'subject_type', 'drive_node',
        'subject_id', v_node."id"::text,
        'summary', v_node."document_number" || ' ' || v_node."name",
        'recipients', to_jsonb(array[v_node."document_owner_id"]),
        'key', 'drive.document_review_due:' || v_node."id"::text || ':' || v_node."next_review_on"::text,
        'data', jsonb_build_object('nodeId', v_node."id", 'documentNumber', v_node."document_number", 'nextReviewOn', v_node."next_review_on")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."drive_nodes" x set "review_notified_for" = v_node."next_review_on" where x."id" = v_node."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.number_format (
  p_tenant uuid,
  p_entity text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_format text;
begin
  v_format := case p_entity
    when 'drive_document' then 'DOC-{n:5}'
    when 'donation_receipt' then 'R-{n}'
    when 'risk' then 'RSK-{n:4}'
    else null
  end;
  return v_format;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pause_lifecycle (
  subject_type text,
  subject_id   text,
  until        timestamp with time zone,
  reason       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', pause_lifecycle.subject_type, 'id', pause_lifecycle.subject_id, 'op', 'pause', 'until', pause_lifecycle.until, 'reason', pause_lifecycle.reason))::text, true);
  case pause_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    when 'change_request' then
      update "public"."change_requests" s set "status" = s."status"
      where s."id" = (pause_lifecycle.subject_id)::uuid;
    when 'drive_node' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.preview_number (
  p_tenant uuid,
  p_entity text,
  p_at     timestamp with time zone DEFAULT now()
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := "better_supabase"."number_format"(p_tenant, p_entity);
  v_period := case p_entity
    when 'drive_document' then ''
    when 'donation_receipt' then ''
    when 'risk' then ''
    else null
  end;
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "better_supabase"."number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = p_entity
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relation_walk (
  tenant       uuid,
  kind         text,
  subject_type text,
  subject_id   text,
  up           boolean,
  max_depth    integer
)
  RETURNS TABLE (
    type  text,
    id    text,
    depth integer
  )
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
  v_inverted boolean;
  v_up boolean;
begin
  select k.canonical, k.inverted into v_kind, v_inverted from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('variant_of', 'variant_of', false, true, true, false, 'variants'), ('variants', 'variant_of', true, true, true, false, 'variant_of'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents'), ('mitigated_by', 'mitigated_by', false, false, false, false, 'mitigates'), ('mitigates', 'mitigated_by', true, false, false, false, 'mitigated_by'), ('materialized_as', 'materialized_as', false, false, false, false, 'materializes'), ('materializes', 'materialized_as', true, false, false, false, 'materialized_as')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = relation_walk.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  v_up := relation_walk.up <> v_inverted;
  return query
  with recursive walk(t, i, d) as (
    select relation_walk.subject_type, relation_walk.subject_id, 0
    union
    select case when v_up then r."target_type" else r."source_type" end,
      case when v_up then r."target_id" else r."source_id" end,
      walk.d + 1
    from "better_supabase"."relations" r join walk on (
      case when v_up then r."source_type" = walk.t and r."source_id" = walk.i
      else r."target_type" = walk.t and r."target_id" = walk.i end)
    where r."tenant_id" = relation_walk.tenant and r."kind" = v_kind
      and walk.d < least(coalesce(relation_walk.max_depth, 100), 100)
  )
  select w.t, w.i, min(w.d)::integer from walk w where w.d > 0
  group by w.t, w.i
  order by min(w.d), w.t, w.i;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relations_by_kind (
  tenant uuid,
  kind   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'kind', r."kind",
    'sourceType', r."source_type", 'sourceId', r."source_id",
    'targetType', r."target_type", 'targetId', r."target_id",
    'data', r."data"
  ) order by r."created_at", r."id"), '[]'::jsonb)
  from (
    select * from "better_supabase"."relations" r
    where r."tenant_id" = relations_by_kind.tenant
      and r."kind" = (select k.canonical from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('variant_of', 'variant_of', false, true, true, false, 'variants'), ('variants', 'variant_of', true, true, true, false, 'variant_of'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents'), ('mitigated_by', 'mitigated_by', false, false, false, false, 'mitigates'), ('mitigates', 'mitigated_by', true, false, false, false, 'mitigated_by'), ('materialized_as', 'materialized_as', false, false, false, false, 'materializes'), ('materializes', 'materialized_as', true, false, false, false, 'materialized_as')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = relations_by_kind.kind)
    order by r."created_at", r."id"
    limit 10000
  ) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.relations_of (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  kind         text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'kind', n.seen, 'direction', e.direction,
    'type', e.other_type, 'subjectId', e.other_id,
    'data', e.data, 'createdAt', e.created_at
  ) order by n.seen, e.created_at, e.id), '[]'::jsonb)
  from (
    select r."id" as id, r."kind" as canonical, 'out' as direction,
      r."target_type" as other_type, r."target_id" as other_id, r."data" as data, r."created_at" as created_at
    from "better_supabase"."relations" r
    where r."tenant_id" = relations_of.tenant and r."source_type" = relations_of.subject_type and r."source_id" = relations_of.subject_id
    union all
    select r."id", r."kind", 'in', r."source_type", r."source_id", r."data", r."created_at"
    from "better_supabase"."relations" r
    where r."tenant_id" = relations_of.tenant and r."target_type" = relations_of.subject_type and r."target_id" = relations_of.subject_id
  ) e
  cross join lateral (
    select case when e.direction = 'in' and not k.both_ways then k.opposite else k.canonical end as seen
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('variant_of', 'variant_of', false, true, true, false, 'variants'), ('variants', 'variant_of', true, true, true, false, 'variant_of'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents'), ('mitigated_by', 'mitigated_by', false, false, false, false, 'mitigates'), ('mitigates', 'mitigated_by', true, false, false, false, 'mitigated_by'), ('materialized_as', 'materialized_as', false, false, false, false, 'materializes'), ('materializes', 'materialized_as', true, false, false, false, 'materialized_as')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite)
    where k.name = e.canonical
  ) n
  where relations_of.kind is null or n.seen = relations_of.kind
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resume_lifecycle (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', resume_lifecycle.subject_type, 'id', resume_lifecycle.subject_id, 'op', 'resume'))::text, true);
  case resume_lifecycle.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    when 'change_request' then
      update "public"."change_requests" s set "status" = s."status"
      where s."id" = (resume_lifecycle.subject_id)::uuid;
    when 'drive_node' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_approval_policy (
  tenant uuid,
  policy jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."approval_policies"%rowtype;
  v_row "better_supabase"."approval_policies"%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_approval_policy.tenant, 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    raise exception 'policy must be an object' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from "better_supabase"."approval_policies" x
    where x."id" = (save_approval_policy.policy ->> 'id')::uuid and x."tenant_id" is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      raise exception 'approval policy not found' using errcode = 'P0002', hint = 'APPROVAL_POLICY_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old."subject_type");
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old."action");
  v_effect := case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old."effect" end;
  if v_type is null or v_action is null or not (exists (
      select 1 from jsonb_array_elements('[{"subjectType":"*","action":"quote.send","effects":["money-movement"]},{"subjectType":"customer","action":"discount","effects":[]},{"subjectType":"customer","action":"refund","effects":[]},{"subjectType":"customer","action":"export","effects":[]},{"subjectType":"drive_node","action":"approve","effects":[]},{"subjectType":"drive_node","action":"release","effects":[]},{"subjectType":"eve_tool_call","action":"add_note","effects":[]},{"subjectType":"workflow_run","action":"approve","effects":[]}]'::jsonb) f
      where (v_type = '*' or f.value ->> 'subjectType' in (v_type, '*'))
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )) then
    raise exception 'a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'APPROVAL_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old."steps", '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  v_steps := (select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) else s end order by o), '[]'::jsonb)
    from jsonb_array_elements(v_steps) with ordinality e(s, o));
  if coalesce(save_approval_policy.policy ->> 'mode', v_old."mode"::text, 'authorize') not in ('confirm', 'authorize') then
    raise exception 'mode must be confirm or authorize' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action", "name", "conditions", "effect", "mode", "steps", "self_approval", "expires_in", "enabled", "created_by", "description")
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name'), v_conditions, v_effect,
      coalesce(save_approval_policy.policy ->> 'mode', 'authorize'), v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false), (save_approval_policy.policy ->> 'expiresIn')::interval,
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true), auth.uid(), case when coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) -> 'description')))."description" else better_supabase.column_default('"better_supabase"."approval_policies"', 'description', (null::"better_supabase"."approval_policies")."description") end)
    returning * into v_row;
  else
    update "better_supabase"."approval_policies" x set
      "subject_type" = v_type,
      "action" = v_action,
      "name" = coalesce(btrim(save_approval_policy.policy ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "effect" = v_effect,
      "mode" = coalesce(save_approval_policy.policy ->> 'mode', x."mode"),
      "steps" = v_steps,
      "self_approval" = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x."self_approval"),
      "expires_in" = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x."expires_in" end,
      "enabled" = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now(), "description" = case when (save_approval_policy.policy -> 'fields') ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', (save_approval_policy.policy -> 'fields') -> 'description')))."description" else x."description" end
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('approval_policy.saved', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.saved',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'saved approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'action', v_row."action", 'effect', v_row."effect", 'name', v_row."name", 'conditions', v_row."conditions", 'mode', v_row."mode", 'steps', v_row."steps", 'selfApproval', v_row."self_approval", 'expiresIn', v_row."expires_in"::text, 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('description', v_row."description"));
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    raise exception 'policy has an invalid name, mode, expiry or flag' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_lifecycle_flag (
  subject_type text,
  subject_id   text,
  flag         text,
  enabled      boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
  v_changed boolean;
begin
  perform set_config('better_supabase.lifecycle_changed', '', true);
  perform set_config('better_supabase.lifecycle_op', (jsonb_build_object('machine', set_lifecycle_flag.subject_type, 'id', set_lifecycle_flag.subject_id, 'op', 'flag', 'flag', set_lifecycle_flag.flag, 'enabled', coalesce(set_lifecycle_flag.enabled, false)))::text, true);
  case set_lifecycle_flag.subject_type
    when 'work_item' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    when 'change_request' then
      update "public"."change_requests" s set "status" = s."status"
      where s."id" = (set_lifecycle_flag.subject_id)::uuid;
    when 'drive_node' then
      raise exception 'the machine has no lifecycle; set lifecycle: true' using errcode = '22023', hint = 'STATE_LIFECYCLE_DISABLED';
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  v_changed := current_setting('better_supabase.lifecycle_changed', true) = '1';
  perform set_config('better_supabase.lifecycle_op', '', true);
  perform set_config('better_supabase.lifecycle_changed', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  return v_changed;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.status_state (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_status text;
  v_tenant text;
  v_step integer;
  v_paused boolean := false;
  v_life "better_supabase"."subject_lifecycles"%rowtype;
  v_order text[];
begin
  case status_state.subject_type
    when 'work_item' then
      select s."state"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."work_items" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_step := array_position('{triage,backlog,unstarted,started,completed}'::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'work_item', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb('{triage,backlog,unstarted,started,completed}'::text[]), 'step', v_step, 'steps', 5, 'progress', case when v_step is null then null when 5 = 1 then 1 else round((v_step - 1)::numeric / 4, 4) end,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    when 'change_request' then
      select s."status"::text, s."organization_id"::text into v_status, v_tenant
      from "public"."change_requests" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;
      select * into v_life from "better_supabase"."subject_lifecycles" x
      where x."subject_type" = 'change_request' and x."subject_id" = status_state.subject_id;
      v_paused := v_life."paused_at" is not null and (v_life."paused_until" is null or v_life."paused_until" > now());
      v_order := coalesce(array(select jsonb_array_elements_text("better_supabase"."lifecycle_graph"(v_life."workflow_version_id") -> 'order')), '{}'::text[]);
      v_step := array_position(v_order, v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'change_request', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb(v_order), 'step', v_step, 'steps', nullif(cardinality(v_order), 0), 'progress', case when v_step is null then null when cardinality(v_order) = 1 then 1 else round((v_step - 1)::numeric / (cardinality(v_order) - 1), 4) end,
        'version', v_life."version", 'flags', to_jsonb(coalesce(v_life."flags", '{}')),
        'paused', v_paused, 'pausedAt', case when v_paused then v_life."paused_at" end,
        'pausedUntil', case when v_paused then v_life."paused_until" end,
        'pauseReason', case when v_paused then v_life."pause_reason" end, 'workflow', 'change-requests', 'workflowVersionId', v_life."workflow_version_id");
    when 'drive_node' then
      select s."document_status"::text, s."tenant_id"::text into v_status, v_tenant
      from "better_supabase"."drive_nodes" s where s."id" = (status_state.subject_id)::uuid;
      if not found then
        raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
      end if;

      v_step := array_position(null::text[], v_status);
      return jsonb_build_object(
        'organizationId', v_tenant, 'subjectType', 'drive_node', 'subjectId', status_state.subject_id,
        'status', v_status, 'order', to_jsonb(null::text[]), 'step', v_step, 'steps', null, 'progress', null,
        'version', null, 'flags', '[]'::jsonb, 'paused', false, 'pausedAt', null, 'pausedUntil', null, 'pauseReason', null);
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.transition (
  subject_type text,
  subject_id   text,
  to_status    text,
  reason       text  DEFAULT NULL::text,
  actor        jsonb DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_found boolean;
begin
  perform set_config('better_supabase.transition_reason', coalesce(transition.reason, ''), true);
  if transition.actor is not null then
    if jsonb_typeof(transition.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(transition.actor ->> 'ip', '')::inet, nullif(transition.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'STATE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(transition.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_status_transition"(text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text, $3::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.subject_id, transition.to_status;
    end if;
  end;
  case transition.subject_type
    when 'work_item' then
      update "better_supabase"."work_items" s set "state" = better_supabase.as_column_type(transition.to_status, (null::"better_supabase"."work_items")."state")
      where s."id" = (transition.subject_id)::uuid;
    when 'change_request' then
      update "public"."change_requests" s set "status" = better_supabase.as_column_type(transition.to_status, (null::"public"."change_requests")."status")
      where s."id" = (transition.subject_id)::uuid;
    when 'drive_node' then
      update "better_supabase"."drive_nodes" s set "document_status" = better_supabase.as_column_type(transition.to_status, (null::"better_supabase"."drive_nodes")."document_status")
      where s."id" = (transition.subject_id)::uuid;
    else
      raise exception 'unknown subject' using errcode = '22023', hint = 'STATE_MACHINE_UNKNOWN';
  end case;
  v_found := found;
  perform set_config('better_supabase.transition_reason', '', true);
  perform set_config('better_supabase.transition_actor', '', true);
  if not v_found then
    raise exception 'no such record, or the caller can''t see it' using errcode = 'P0002', hint = 'STATE_SUBJECT_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_status_transition"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using transition.subject_type, transition.to_status;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unassign_acknowledgement (
  assignment_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."acknowledgement_assignments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."acknowledgement_assignments" x where x."id" = unassign_acknowledgement.assignment_id for update;
  if not found then
    raise exception 'acknowledgement assignment not found' using errcode = 'P0002', hint = 'ACKNOWLEDGEMENT_ASSIGNMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'acknowledgements.manage'), false) and case v_row."subject_type"
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'compliance.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id" and (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end)) then
    raise exception 'not allowed to remove acknowledgement assignments on this record' using errcode = '42501', hint = 'ACKNOWLEDGEMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."acknowledgement_assignments" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('acknowledgement_assignment.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id"), 'acknowledgement-assignments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/acknowledgements');
  perform better_supabase.audit_event(
    event_type => 'acknowledgement_assignment.deleted',
    category => 'data',
    target_type => 'acknowledgement_assignment',
    record_id => v_row."id"::text,
    summary => 'removed the acknowledgement assignment of ' || v_row."principal_type" || ' ' || v_row."principal_id" || ' on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'assignmentId', v_row."id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'principalType', v_row."principal_type", 'principalId', v_row."principal_id", 'dueInDays', v_row."due_in_days", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlink (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', unlink.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to unlink records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('variant_of', 'variant_of', false, true, true, false, 'variants'), ('variants', 'variant_of', true, true, true, false, 'variant_of'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents'), ('mitigated_by', 'mitigated_by', false, false, false, false, 'mitigates'), ('mitigates', 'mitigated_by', true, false, false, false, 'mitigated_by'), ('materialized_as', 'materialized_as', false, false, false, false, 'materializes'), ('materializes', 'materialized_as', true, false, false, false, 'materialized_as')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = unlink.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := unlink.target_type; v_source_id := unlink.target_id;
    v_target_type := unlink.source_type; v_target_id := unlink.source_id;
  else
    v_source_type := unlink.source_type; v_source_id := unlink.source_id;
    v_target_type := unlink.target_type; v_target_id := unlink.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case unlink.source_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'compliance.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'risks.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant and (coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end)
     or not (case unlink.target_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'compliance.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'risks.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant and (coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end) then
    raise exception 'not allowed to unlink these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."relations"
    where "tenant_id" = unlink.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id
    returning * into v_old;
  if v_old."id" is null then
    return jsonb_build_object('removed', false, 'data', null);
  end if;
  perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', unlink.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (unlink.tenant)::text, null, 'better-supabase/relations');
  return jsonb_build_object('removed', true, 'data', v_old."data");
end;
$function$;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD CONSTRAINT "bsb_drive_nodes_document_file" CHECK (((document_status IS NULL) OR (kind = 'file'::text)));

ALTER TABLE "better_supabase"."drive_nodes"
  ADD CONSTRAINT "bsb_drive_nodes_effective_version" FOREIGN KEY (effective_version_id) REFERENCES better_supabase.versions(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."drive_nodes"
  ADD CONSTRAINT "drive_nodes_document_number_check" CHECK (((length(document_number) >= 1) AND (length(document_number) <= 100)));

ALTER TABLE "better_supabase"."drive_nodes"
  ADD CONSTRAINT "drive_nodes_document_status_check" CHECK ((document_status = ANY (ARRAY['draft'::text, 'in_review'::text, 'effective'::text, 'obsolete'::text])));

ALTER TABLE "better_supabase"."drive_nodes"
  ADD CONSTRAINT "drive_nodes_document_type_check" CHECK (((length(document_type) >= 1) AND (length(document_type) <= 63)));

ALTER TABLE "better_supabase"."drive_nodes"
  ADD CONSTRAINT "drive_nodes_review_interval_months_check" CHECK (((review_interval_months >= 1) AND (review_interval_months <= 120)));

CREATE UNIQUE INDEX drive_nodes_document_number_idx ON better_supabase.drive_nodes USING btree (tenant_id, document_number)
  WHERE (document_number IS NOT NULL);

CREATE INDEX drive_nodes_document_owner_idx ON better_supabase.drive_nodes USING btree (document_owner_id)
  WHERE (document_owner_id IS NOT NULL);

CREATE INDEX drive_nodes_effective_version_idx ON better_supabase.drive_nodes USING btree (effective_version_id)
  WHERE (effective_version_id IS NOT NULL);

CREATE INDEX drive_nodes_next_review_idx ON better_supabase.drive_nodes USING btree (next_review_on)
  WHERE (document_status = 'effective'::text);

CREATE TRIGGER bsb_transition_drive_node
  BEFORE INSERT OR UPDATE OF document_status ON better_supabase.drive_nodes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_transition_drive_node();

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."status_history"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    ELSE false
END));

CREATE POLICY "status_history_read" ON "better_supabase"."status_history"
  FOR SELECT
  TO "authenticated"
  USING (
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE (s.id = (status_history.subject_id)::uuid)))
    ELSE false
END);

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."status_stages"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    ELSE false
END));

CREATE POLICY "status_stages_read" ON "better_supabase"."status_stages"
  FOR SELECT
  TO "authenticated"
  USING (
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE (s.id = (status_stages.subject_id)::uuid)))
    ELSE false
END);

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."subject_lifecycles"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    ELSE false
END));

CREATE POLICY "subject_lifecycles_read" ON "better_supabase"."subject_lifecycles"
  FOR SELECT
  TO "authenticated"
  USING (
CASE subject_type
    WHEN 'work_item'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE (s.id = (subject_lifecycles.subject_id)::uuid)))
    ELSE false
END);

COMMENT ON CONSTRAINT "bsb_drive_nodes_document_file" ON "better_supabase"."drive_nodes" IS 'better-supabase check 3f65769f';

REVOKE ALL ON FUNCTION "api"."drive_document_obsolete"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_document_obsolete"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_document_release"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_document_release"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."drive_document_review"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_document_review"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_document_save"(uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_document_save"(uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_document_submit"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_document_submit"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."drive_documents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_documents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."notify_due_drive_reviews"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notify_due_drive_reviews"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_document_decided"(uuid, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drive_document_obsolete"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_document_obsolete"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_document_readable"(uuid, uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."drive_document_release"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_document_release"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_document_review"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_document_review"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_document_save"(uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_document_save"(uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_document_submit"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_document_submit"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_documents"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_documents"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."notify_due_drive_reviews"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notify_due_drive_reviews"() TO "service_role";
