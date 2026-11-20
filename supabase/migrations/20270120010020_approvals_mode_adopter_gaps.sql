SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."leave_requests"
  ADD COLUMN "rejected_at" timestamp WITH time zone;

ALTER TABLE "better_supabase"."leave_requests"
  ADD COLUMN "decided_by" uuid;

ALTER TABLE "better_supabase"."leave_requests"
  ADD COLUMN "decision_note" text;

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
  if v_req."subject_type" = 'support_request' then
    perform "better_supabase"."apply_support_approval"(v_req."subject_id"::uuid, auth.uid());
  end if;
  if v_req."subject_type" = 'ai_tool_approval' then
    perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", true, (select x."comment" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" order by x."created_at" desc, x."id" desc limit 1));
  end if;
  if v_req."subject_type" = 'access_request' then
    perform "better_supabase"."grant_access_request"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'purchase_requisition' then
    perform "better_supabase"."purchase_requisition_decided"(v_req."subject_id"::uuid, true);
  end if;
  if v_req."subject_type" = 'drive_node' then
    perform "better_supabase"."drive_document_decided"(v_req."id", true);
  end if;
  if v_req."subject_type" = 'timesheet' then
    perform "better_supabase"."approve_timesheet"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'leave_request' then
    perform "better_supabase"."leave_approval_decided"(v_req."subject_id"::uuid, 'approved', (select x."comment" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" order by x."created_at" desc, x."id" desc limit 1), (select x."approver" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" and x."decision" = 'approved' order by x."created_at" desc, x."id" desc limit 1));
  end if;
  if v_req."subject_type" = 'expense_report' then
    perform "better_supabase"."approve_expense_report"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'content_entry' then
    perform "better_supabase"."content_entry_approved"((v_req."subject_id")::uuid);
  end if;
  if v_req."subject_type" = 'care_plan_action' then
    perform "better_supabase"."care_plan_action_approved"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'case' then
    perform "better_supabase"."case_close_approved"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'warranty_claim' then
    perform "better_supabase"."decide_warranty_claim"(v_req."subject_id"::uuid, 'approved', (select x."comment" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" order by x."created_at" desc, x."id" desc limit 1));
  end if;
  if v_req."subject_type" = 'appraisal' then
    perform "better_supabase"."appraisal_approved"(v_req."subject_id"::uuid);
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

CREATE OR REPLACE FUNCTION better_supabase.cancel_approval (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = cancel_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.manage'), false)) then
    raise exception 'only the requester or a manager can cancel this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if v_req."status" <> 'pending' then
    raise exception 'this request is no longer pending' using errcode = '22023', hint = 'APPROVAL_CLOSED';
  end if;
  update "better_supabase"."approval_requests" r set "status" = 'cancelled', "decided_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  perform "better_supabase".emit_event('approval.cancelled', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.cancelled',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'cancelled' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  if v_req."subject_type" = 'leave_request' then
    perform "better_supabase"."leave_approval_decided"(v_req."subject_id"::uuid, 'cancelled', null, auth.uid());
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
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
  if exists (select 1 from "better_supabase"."approval_items" x where x."request_id" = v_req."id") then
    raise exception 'this request has items; use decide_approval_items' using errcode = '22023', hint = 'APPROVAL_ITEMS_REQUIRED';
  end if;
  if v_service then
    if v_actor is not null and v_actor = v_req."requested_by" and coalesce(v_req."policy" ->> 'mode', 'authorize') <> 'confirm'
      and not coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) then
      raise exception 'the requester can''t decide their own request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
    end if;
    if v_actor is not null and coalesce(v_req."policy" -> 'excludedUserIds', '[]'::jsonb) ? v_actor::text then
      raise exception 'this user is left out of deciding this request' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
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
    if v_req."subject_type" = 'support_request' then
      perform "better_supabase"."close_support_request"(v_req."subject_id"::uuid);
    end if;
    if v_req."subject_type" = 'ai_tool_approval' then
      perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", false, decide_approval.comment);
    end if;
    if v_req."subject_type" = 'purchase_requisition' then
      perform "better_supabase"."purchase_requisition_decided"(v_req."subject_id"::uuid, false);
    end if;
    if v_req."subject_type" = 'drive_node' then
      perform "better_supabase"."drive_document_decided"(v_req."id", false);
    end if;
    if v_req."subject_type" = 'leave_request' then
      perform "better_supabase"."leave_approval_decided"(v_req."subject_id"::uuid, 'rejected', decide_approval.comment, v_actor);
    end if;
    if v_req."subject_type" = 'warranty_claim' then
      perform "better_supabase"."decide_warranty_claim"(v_req."subject_id"::uuid, 'denied', decide_approval.comment);
    end if;
    if v_req."subject_type" = 'appraisal' then
      perform "better_supabase"."appraisal_rejected"(v_req."subject_id"::uuid);
    end if;
  else
    select count(*) into v_count from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved';
    if v_req."policy" ->> 'mode' = 'confirm' and v_req."requested_by" = v_actor then
      update "better_supabase"."approval_requests" r set "status" = 'approved', "decided_at" = now()
        where r."id" = v_req."id" returning * into v_req;
      perform "better_supabase"."approval_finalize"(v_req."id");
    elsif (case when coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'all')::boolean, false)
        and not coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'escalated')::boolean, false)
      then jsonb_array_length(coalesce(v_req."policy" -> 'steps' -> v_req."step" -> 'approvers' -> 'users', '[]'::jsonb)) > 0
        and not exists (
          select 1 from jsonb_array_elements_text(v_req."policy" -> 'steps' -> v_req."step" -> 'approvers' -> 'users') u(id)
          where not exists (
            select 1 from "better_supabase"."approval_decisions" x
            where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'approved'
              and (x."approver" = u.id::uuid or exists (
                select 1 from "better_supabase"."approval_decisions" y
                where y."request_id" = x."request_id" and y."step" = x."step" and y."decision" = 'delegated'
                  and y."approver" = u.id::uuid and y."delegate_to" = x."approver"
              ))
          )
        )
      else v_count >= coalesce((v_req."policy" -> 'steps' -> v_req."step" ->> 'required')::integer, 1) end) then
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

CREATE OR REPLACE FUNCTION better_supabase.leave_approval_decided (
  request_id uuid,
  decision   text,
  note       text,
  decided_by uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."leave_requests"%rowtype;
begin
  if leave_approval_decided.decision = 'approved' then
    perform "better_supabase"."approve_leave_request"(leave_approval_decided.request_id);
    update "better_supabase"."leave_requests" x set "updated_at" = now(), "decided_by" = leave_approval_decided.decided_by, "decision_note" = nullif(trim(leave_approval_decided.note), '')
      where x."id" = leave_approval_decided.request_id and x."approved_at" is not null and x."cancelled_at" is null;
  elsif leave_approval_decided.decision = 'rejected' then
    update "better_supabase"."leave_requests" x set "updated_at" = now(), "rejected_at" = now(), "decided_by" = leave_approval_decided.decided_by, "decision_note" = nullif(trim(leave_approval_decided.note), '')
      where x."id" = leave_approval_decided.request_id and x."approved_at" is null and x."cancelled_at" is null
      returning * into v_row;
    if found then
      perform "better_supabase".emit_event('leave_request.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.rejected',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'rejected leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
    end if;
  elsif leave_approval_decided.decision = 'cancelled' then
    update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = leave_approval_decided.decided_by, "updated_at" = now()
      where x."id" = leave_approval_decided.request_id and x."approved_at" is null and x."cancelled_at" is null
      returning * into v_row;
    if found then
      perform "better_supabase".emit_event('leave_request.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.cancelled',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'cancelled leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
    end if;
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sole_owned_organizations (
  member uuid DEFAULT NULL::uuid
)
  RETURNS uuid[]
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_member uuid := coalesce(member, auth.uid());
  v_all boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_member = auth.uid();
begin
  if v_member is null then
    raise exception 'Only the member or the service role can read this' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return coalesce((
    select array_agg(m."organization_id" order by m."organization_id")
    from "public"."memberships" m
    where m."user_id" = v_member and (select r."key" from "better_supabase"."roles" r where r."id" = m."role") = 'owner'
      and (v_all or coalesce(better_supabase.member_can(auth.uid(), m."organization_id", 'members.remove'), false))
      and exists (select 1 from "public"."organizations" o where o."id" = m."organization_id")
      and not exists (
        select 1 from "public"."memberships" y
        where y."organization_id" = m."organization_id" and y."user_id" <> v_member and (select r."key" from "better_supabase"."roles" r where r."id" = y."role") = 'owner'
      )
  ), '{}');
end;
$function$;

ALTER TABLE "better_supabase"."leave_requests"
  ADD CONSTRAINT "bsb_leave_requests_decision_note_check" CHECK (((decision_note IS NULL) OR (length(decision_note) <= 2000)));

REVOKE ALL ON FUNCTION "better_supabase"."leave_approval_decided"(uuid, text, text, uuid) FROM PUBLIC;
