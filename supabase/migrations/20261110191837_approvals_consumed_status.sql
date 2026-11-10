SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.consume_approval (
  request_id  uuid,
  fingerprint text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = consume_approval.request_id for update;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.manage'), false)) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if v_req."consumed_at" is not null then
    raise exception 'this approval was already used' using errcode = '22023', hint = 'APPROVAL_CONSUMED';
  end if;
  if v_req."status" <> 'approved' then
    raise exception 'this request is not approved' using errcode = '22023', hint = 'APPROVAL_NOT_APPROVED';
  end if;
  if v_req."fingerprint" is distinct from consume_approval.fingerprint then
    raise exception 'the request changed after it was approved; ask for approval again' using errcode = '22023', hint = 'APPROVAL_FINGERPRINT_MISMATCH';
  end if;
  update "better_supabase"."approval_requests" r set "status" = 'consumed', "consumed_at" = now()
    where r."id" = v_req."id" returning * into v_req;
  perform "better_supabase".emit_event('approval.consumed', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.consumed',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'consumed' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.is_approved (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce((
    select x."status"::text in ('approved', 'consumed') from "better_supabase"."approval_requests" x
    where x."subject_type" = is_approved.subject_type and x."subject_id" = is_approved.subject_id and x."action" = is_approved.action
    order by x."created_at" desc limit 1
  ), false)
$function$;
