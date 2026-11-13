SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."support_requests"
  DROP CONSTRAINT "support_requests_target_user_id_fkey";

ALTER TABLE "better_supabase"."support_sessions"
  DROP CONSTRAINT "support_sessions_target_user_id_fkey";

CREATE OR REPLACE FUNCTION api.rotate_field_key (
  owner text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rotate_field_key"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.active_support_session (
  session_id uuid,
  admin_id   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
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
  )
  from "better_supabase"."support_sessions" s
  where s."id" = $1
    and s."ended_at" is null
    and s."expires_at" > now()
    and case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then s."admin_id" = $2
      else s."admin_id" = auth.uid() and "better_supabase"."is_platform"('impersonation.start')
    end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.apply_support_approval (
  request_id uuid,
  approver   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."support_requests";
begin
  select * into v_row from "better_supabase"."support_requests" x where x."id" = request_id for update;
  if not found then
    raise exception 'No support request %', request_id using errcode = 'P0002', hint = 'IMPERSONATION_REQUEST_MISSING';
  end if;
  if approver is null then
    raise exception 'Not allowed to approve a support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
  end if;
  if v_row."admin_id" = approver then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'IMPERSONATION_SELF_APPROVAL';
  end if;
  if v_row."approved_by" is not null then
    if v_row."approved_by" = approver then
      return jsonb_build_object(
    'id', v_row."id",
    'admin_id', v_row."admin_id",
    'target_user_id', v_row."target_id",
    'reason', v_row."reason",
    'tenant', v_row."tenant_id",
    'read_only', v_row."read_only",
    'metadata', v_row."metadata",
    'requested_at', v_row."requested_at",
    'expires_at', v_row."expires_at",
    'approved_by', v_row."approved_by",
    'approved_at', v_row."approved_at",
    'session_id', v_row."session_id"
  );
    end if;
    raise exception 'Support request % is already approved', request_id using errcode = 'P0001', hint = 'IMPERSONATION_REQUEST_DECIDED';
  end if;
  if v_row."session_id" is not null or v_row."expires_at" <= now() then
    raise exception 'Support request % has expired or was used', request_id using errcode = 'P0001', hint = 'IMPERSONATION_REQUEST_CLOSED';
  end if;
  update "better_supabase"."support_requests" x set "approved_by" = approver, "approved_at" = now()
  where x."id" = request_id
  returning * into v_row;
  perform "better_supabase"."approval_settle"('support_request', request_id::text, 'start', 'approved', approver);
  return jsonb_build_object(
    'id', v_row."id",
    'admin_id', v_row."admin_id",
    'target_user_id', v_row."target_id",
    'reason', v_row."reason",
    'tenant', v_row."tenant_id",
    'read_only', v_row."read_only",
    'metadata', v_row."metadata",
    'requested_at', v_row."requested_at",
    'expires_at', v_row."expires_at",
    'approved_by', v_row."approved_by",
    'approved_at', v_row."approved_at",
    'session_id', v_row."session_id"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approved_support_request (
  target    uuid,
  tenant    uuid    DEFAULT NULL::uuid,
  read_only boolean DEFAULT true,
  admin_id  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'admin_id', x."admin_id",
    'target_user_id', x."target_id",
    'reason', x."reason",
    'tenant', x."tenant_id",
    'read_only', x."read_only",
    'metadata', x."metadata",
    'requested_at', x."requested_at",
    'expires_at', x."expires_at",
    'approved_by', x."approved_by",
    'approved_at', x."approved_at",
    'session_id', x."session_id"
  )
  from "better_supabase"."support_requests" x
  where x."admin_id" = case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then $4 else auth.uid() end
    and x."target_id" = $1
    and x."tenant_id" is not distinct from $2
    and (not x."read_only" or coalesce($3, true))
    and x."approved_by" is not null
    and x."approved_by" <> case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then $4 else auth.uid() end
    and x."session_id" is null
    and x."expires_at" > now()
  order by x."approved_at" desc
  limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.client_notes_seal()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_owner text := 'tenant:' || (new."organization_id")::text;
  v_old_owner text;
  v_moved boolean := false;
  v_key text;
begin
  if tg_op = 'UPDATE' then
    v_old_owner := 'tenant:' || (old."organization_id")::text;
    v_moved := v_owner is distinct from v_old_owner;
  end if;
  if new."diagnosis" is not null and left(new."diagnosis", 5) is distinct from 'bsf1:' then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."diagnosis" := "better_supabase"."field_seal"(v_key, new."diagnosis");
  elsif new."diagnosis" is not null and v_moved and not (case when tg_op = 'INSERT' then true else new."diagnosis" is distinct from old."diagnosis" end) then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."diagnosis" := "better_supabase"."field_seal"(v_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."diagnosis"));
  end if;
  if new."birth_date" is not null and left(new."birth_date", 5) is distinct from 'bsf1:' then
    new."birth_date" := ((new."birth_date")::date)::text;
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."birth_date" := "better_supabase"."field_seal"(v_key, new."birth_date");
  elsif new."birth_date" is not null and v_moved and not (case when tg_op = 'INSERT' then true else new."birth_date" is distinct from old."birth_date" end) then
    v_key := coalesce(v_key, "better_supabase"."field_key"(v_owner, true));
    new."birth_date" := "better_supabase"."field_seal"(v_key, "better_supabase"."field_open"("better_supabase"."field_key"(v_old_owner, false), new."birth_date"));
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_native_subscription (
  tenant           uuid,
  plan             text,
  currency         text,
  unit_amount      bigint,
  quantity         integer                  DEFAULT 1,
  billing_interval text                     DEFAULT 'month'::text,
  started_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_start timestamptz := coalesce(create_native_subscription.started_at, now());
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role creates native subscriptions' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  insert into "better_supabase"."billing_native_subscriptions" ("tenant_id", "plan", "currency", "unit_amount", "quantity", "billing_interval", "period_starts_at", "period_ends_at")
  values (create_native_subscription.tenant, create_native_subscription.plan, upper(create_native_subscription.currency), create_native_subscription.unit_amount,
    coalesce(create_native_subscription.quantity, 1), coalesce(create_native_subscription.billing_interval, 'month'), v_start,
    v_start + ('1 ' || coalesce(create_native_subscription.billing_interval, 'month'))::interval)
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'plan', v_row."plan", 'currency', v_row."currency",
    'unit_amount', v_row."unit_amount"::text, 'quantity', v_row."quantity", 'interval', v_row."billing_interval",
    'period_starts_at', v_row."period_starts_at", 'period_ends_at', v_row."period_ends_at");
exception when check_violation or invalid_text_representation then
  raise exception 'The subscription is invalid' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.end_support_session (
  session_id uuid,
  ended_by   text DEFAULT 'admin'::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  ended jsonb;
begin
  if service and ended_by not in ('admin', 'expired', 'revoked') then
    raise exception 'ended_by must be admin, expired or revoked' using errcode = '22023';
  end if;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = case
      when service then ended_by
      when s."admin_id" = auth.uid() then 'admin'
      else 'revoked'
    end
  where s."id" = session_id and s."ended_at" is null
    and (service or s."admin_id" = auth.uid()
      or "better_supabase"."is_platform"('impersonation.revoke'))
  returning jsonb_build_object(
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
  ) into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_end"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform "better_supabase".emit_event('support_session.ended', jsonb_build_object('sessionId', ended ->> 'id', 'adminId', ended ->> 'admin_id', 'targetUserId', ended ->> 'target_user_id', 'reason', ended ->> 'reason', 'readOnly', (ended ->> 'read_only')::boolean, 'expiresAt', ended ->> 'expires_at', 'organizationId', ended ->> 'tenant', 'endedBy', ended_by), 'support-sessions/' || session_id, ((ended ->> 'tenant')::uuid)::text, 'support_session.ended:' || session_id, 'better-supabase/impersonation');
  perform better_supabase.audit_event(
    event_type => 'support_session.ended',
    category => 'security',
    target_type => 'user',
    record_id => ended ->> 'target_user_id',
    tenant => ((ended ->> 'tenant')::uuid)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'ended_by', ended_by),
    idempotency_key => 'support_session.ended:' || session_id,
    actor_id => case when service then (ended ->> 'admin_id')::uuid else auth.uid() end,
    support_session => session_id,
    impersonated_by => (ended ->> 'admin_id')::uuid,
    impersonation_reason => ended ->> 'reason'
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expire_support_sessions()
  RETURNS SETOF jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  expired_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role expires support sessions' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
  end if;
  for expired_id in
    select s."id" from "better_supabase"."support_sessions" s
    where s."ended_at" is null and s."expires_at" <= now()
    order by s."expires_at"
    for update skip locked
  loop
    if "better_supabase"."end_support_session"(expired_id, 'expired') then
      return next (select jsonb_build_object(
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
  ) from "better_supabase"."support_sessions" s where s."id" = expired_id);
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_key_status()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
begin
  if (select auth.uid()) is null and not v_service then
    raise exception 'only signed-in users and the service role read field key status' using errcode = '42501', hint = 'FIELD_KEY_STATUS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'owner', o.owner,
      'has_key', k.id is not null,
      'has_lookup_key', l.id is not null,
      'key_created_at', k.created_at,
      'key_rotated_at', nullif(k.updated_at, k.created_at),
      'lookup_key_created_at', l.created_at,
      'columns', case when o.owner like 'tenant:%' then '[{"table":"client_notes","column":"diagnosis"},{"table":"client_notes","column":"birth_date"}]'::jsonb when o.owner like 'user:%' then '[]'::jsonb when o.owner = 'app' then '[]'::jsonb else '[]'::jsonb end,
      'fields', coalesce((select count(*) from "better_supabase"."field_definitions" d where d."encrypted" and 'tenant:' || (d."tenant_id")::text = o.owner), 0)
    ) order by o.owner)
    from (
      select substr(s.name, 14) as owner
      from vault.secrets s
      where v_service and left(s.name, 13) = 'bs:field-key:'
      union
      select 'tenant:' || (m.id)::text
      from better_supabase.member_organization_ids() as m(id)
      where not v_service
    ) o
    left join vault.secrets k on k.name = 'bs:field-key:' || o.owner
    left join vault.secrets l on l.name = 'bs:field-lookup-key:' || o.owner
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_support_sessions (
  admin_id uuid    DEFAULT NULL::uuid,
  target   uuid    DEFAULT NULL::uuid,
  active   boolean DEFAULT NULL::boolean,
  max_rows integer DEFAULT 50
)
  RETURNS SETOF jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
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
  )
  from "better_supabase"."support_sessions" s
  where (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or "better_supabase"."is_platform"('impersonation.read'))
    and ($1 is null or s."admin_id" = $1)
    and ($2 is null or s."target_id" = $2)
    and ($3 is null
      or $3 = (s."ended_at" is null and s."expires_at" > now()))
  order by s."started_at" desc
  limit $4
$function$;

CREATE OR REPLACE FUNCTION better_supabase.operation_permission (
  op text
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case op
    when 'access-requests.create' then 'access_requests.create'
    when 'access-requests.emergency' then 'access_requests.emergency'
    when 'access-requests.manage' then 'access_requests.manage'
    when 'access-requests.read' then 'access_requests.read'
    when 'access-requests.review' then 'access_requests.review'
    when 'accounting.close' then 'accounting.close'
    when 'accounting.manage' then 'accounting.manage'
    when 'accounting.post' then 'accounting.post'
    when 'accounting.read' then 'accounting.read'
    when 'accounting.write' then 'accounting.write'
    when 'acknowledgements.acknowledge' then 'acknowledgements.acknowledge'
    when 'acknowledgements.manage' then 'acknowledgements.manage'
    when 'acknowledgements.read' then 'acknowledgements.read'
    when 'activities.manage' then 'activities.manage'
    when 'activities.read' then 'activities.read'
    when 'activities.readRestricted' then 'activities.read_restricted'
    when 'activities.write' then 'activities.write'
    when 'advisories.publish' then 'advisories.publish'
    when 'advisories.read' then 'advisories.read'
    when 'advisories.write' then 'advisories.write'
    when 'agent-checkout.manage' then 'agent_checkout.manage'
    when 'agent-checkout.read' then 'agent_checkout.read'
    when 'agent-checkout.write' then 'agent_checkout.write'
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.create' then 'ai_chat.create'
    when 'ai-chat.manage' then 'ai_chat.manage'
    when 'ai-chat.moderate' then 'ai_chat.moderate'
    when 'ai-chat.read' then 'ai_chat.read'
    when 'ai-chat.share' then 'ai_chat.share'
    when 'ai-files.manage' then 'ai_files.manage'
    when 'ai-files.upload' then 'ai_files.upload'
    when 'ai-keys.manage' then 'ai_keys.manage'
    when 'ai-keys.use' then 'ai_keys.use'
    when 'ai-schedules.create' then 'ai_schedules.write'
    when 'ai-schedules.manage' then 'ai_schedules.manage'
    when 'announcements.manage' then 'announcements.manage'
    when 'api-keys.manage' then 'api_keys.manage'
    when 'api-keys.own' then 'api_keys.own'
    when 'appraisals.manage' then 'appraisals.manage'
    when 'appraisals.read' then 'appraisals.read'
    when 'appraisals.review' then 'appraisals.review'
    when 'approvals.manage' then 'approvals.manage'
    when 'approvals.read' then 'approvals.read'
    when 'approvals.request' then 'approvals.request'
    when 'assets.assign' then 'assets.assign'
    when 'assets.manage' then 'assets.manage'
    when 'assets.read' then 'assets.read'
    when 'assignment.assign' then 'assignment.assign'
    when 'assignment.manage' then 'assignment.manage'
    when 'assignment.read' then 'assignment.read'
    when 'attachments.manage' then 'attachments.manage'
    when 'attachments.read' then 'attachments.read'
    when 'attachments.upload' then 'attachments.upload'
    when 'audit.read' then 'audit.read'
    when 'audit.readAll' then 'audit.read'
    when 'audit.revert' then 'audit.revert'
    when 'automations.manage' then 'automations.manage'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'automations.write' then 'automations.write'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'billing.manage' then 'billing.manage'
    when 'billing.read' then 'billing.read'
    when 'billing.readAll' then 'billing.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk-actions.run' then 'bulk_actions.run'
    when 'calendar.manage' then 'calendar.manage'
    when 'calendar.read' then 'calendar.read'
    when 'calendar.write' then 'calendar.write'
    when 'care-plans.evaluate' then 'care_plans.evaluate'
    when 'care-plans.manage' then 'care_plans.manage'
    when 'care-plans.publish' then 'care_plans.publish'
    when 'care-plans.read' then 'care_plans.read'
    when 'care-plans.write' then 'care_plans.write'
    when 'cases.close' then 'cases.close'
    when 'cases.create' then 'cases.create'
    when 'cases.manage' then 'cases.manage'
    when 'cases.read' then 'cases.read'
    when 'cases.write' then 'cases.write'
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'clinical-decision-support.manage' then 'clinical_decision_support.manage'
    when 'clinical-decision-support.read' then 'clinical_decision_support.read'
    when 'clinical-decision-support.write' then 'clinical_decision_support.write'
    when 'collections.read' then 'collections.read'
    when 'collections.share' then 'collections.share'
    when 'collections.write' then 'collections.write'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'commissions.manage' then 'commissions.manage'
    when 'commissions.read' then 'commissions.read'
    when 'commissions.write' then 'commissions.write'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
    when 'contacts.approveSupplier' then 'contacts.approve_supplier'
    when 'contacts.manage' then 'contacts.manage'
    when 'contacts.read' then 'contacts.read'
    when 'contacts.write' then 'contacts.write'
    when 'content.publish' then 'content.publish'
    when 'content.read' then 'content.read'
    when 'content.write' then 'content.write'
    when 'contracts.manage' then 'contracts.manage'
    when 'contracts.read' then 'contracts.read'
    when 'contracts.write' then 'contracts.write'
    when 'courses.enroll' then 'courses.enroll'
    when 'courses.manage' then 'courses.manage'
    when 'courses.read' then 'courses.read'
    when 'custom-fields.manage' then 'custom_fields.manage'
    when 'custom-fields.read' then 'custom_fields.read'
    when 'custom-fields.sensitive' then 'custom_fields.read_sensitive'
    when 'dam.read' then 'dam.read'
    when 'dam.write' then 'dam.write'
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deadlines.manage' then 'deadlines.manage'
    when 'deadlines.read' then 'deadlines.read'
    when 'deadlines.write' then 'deadlines.write'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'document-templates.manage' then 'document_templates.manage'
    when 'document-templates.read' then 'document_templates.read'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'domains.manage' then 'domains.manage'
    when 'domains.read' then 'domains.read'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
    when 'e-prescribing.manage' then 'e_prescribing.manage'
    when 'e-prescribing.read' then 'e_prescribing.read'
    when 'e-prescribing.sign' then 'e_prescribing.sign'
    when 'e-prescribing.write' then 'e_prescribing.write'
    when 'employees.read' then 'employees.read'
    when 'employees.readSensitive' then 'employees.read_sensitive'
    when 'employees.write' then 'employees.write'
    when 'enrichment.read' then 'enrichment.read'
    when 'enrichment.run' then 'enrichment.run'
    when 'enrollments.enroll' then 'enrollments.enroll'
    when 'enrollments.manage' then 'enrollments.manage'
    when 'enrollments.read' then 'enrollments.read'
    when 'expenses.approve' then 'expenses.approve'
    when 'expenses.manage' then 'expenses.manage'
    when 'expenses.read' then 'expenses.read'
    when 'expenses.submit' then 'expenses.submit'
    when 'field-encryption.manage' then 'field_encryption.manage'
    when 'field-history.read' then 'field_history.read'
    when 'flags.manage' then 'flags.manage'
    when 'forecasts.read' then 'forecasts.read'
    when 'forecasts.snapshot' then 'forecasts.snapshot'
    when 'forms.manage' then 'forms.manage'
    when 'forms.read' then 'forms.read'
    when 'forms.review' then 'forms.review'
    when 'forms.submit' then 'forms.submit'
    when 'funding.approve' then 'funding.approve'
    when 'funding.claim' then 'funding.claim'
    when 'funding.manage' then 'funding.manage'
    when 'funding.read' then 'funding.read'
    when 'funding.register' then 'funding.register'
    when 'funding.write' then 'funding.write'
    when 'goals.manage' then 'goals.manage'
    when 'goals.read' then 'goals.read'
    when 'guests.manage' then 'guests.manage'
    when 'guests.read' then 'guests.read'
    when 'hiring.manage' then 'hiring.manage'
    when 'hiring.read' then 'hiring.read'
    when 'hiring.write' then 'hiring.write'
    when 'impersonation.read' then 'impersonation.read'
    when 'impersonation.revoke' then 'impersonation.revoke'
    when 'impersonation.start' then 'impersonation.start'
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'incoming-webhooks.create' then 'webhooks.manage'
    when 'incoming-webhooks.delete' then 'webhooks.manage'
    when 'incoming-webhooks.read' then 'webhooks.read'
    when 'incoming-webhooks.update' then 'webhooks.manage'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.read' then 'members.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invoices.approve' then 'invoices.approve'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.send' then 'invoices.send'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
    when 'leave.approve' then 'leave.approve'
    when 'leave.manage' then 'leave.manage'
    when 'leave.read' then 'leave.read'
    when 'leave.request' then 'leave.request'
    when 'ledger.manage' then 'ledger.manage'
    when 'ledger.post' then 'ledger.post'
    when 'ledger.read' then 'ledger.read'
    when 'legal-entities.manage' then 'legal_entities.manage'
    when 'legal-entities.read' then 'legal_entities.read'
    when 'lims.manage' then 'lims.manage'
    when 'lims.read' then 'lims.read'
    when 'lims.write' then 'lims.write'
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'maintenance.manage' then 'maintenance.manage'
    when 'maintenance.read' then 'maintenance.read'
    when 'maintenance.record' then 'maintenance.record'
    when 'manufacturing.manage' then 'manufacturing.manage'
    when 'manufacturing.produce' then 'manufacturing.produce'
    when 'manufacturing.read' then 'manufacturing.read'
    when 'manufacturing.write' then 'manufacturing.write'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
    when 'meetings.manage' then 'meetings.manage'
    when 'meetings.read' then 'meetings.read'
    when 'meetings.write' then 'meetings.write'
    when 'memory.manage' then 'memory.manage'
    when 'memory.read' then 'memory.read'
    when 'messaging.moderate' then 'messages.moderate'
    when 'messaging.read' then 'messages.read'
    when 'messaging.send' then 'messages.send'
    when 'metrics.manage' then 'metrics.manage'
    when 'metrics.read' then 'metrics.read'
    when 'moderation.ban' then 'moderation.ban'
    when 'moderation.manage' then 'moderation.manage'
    when 'moderation.read' then 'moderation.read'
    when 'moderation.report' then 'moderation.report'
    when 'notifications.read' then 'notifications.read'
    when 'notifications.send' then 'notifications.send'
    when 'numbering.assign' then 'numbering.assign'
    when 'observations.manage' then 'observations.manage'
    when 'observations.read' then 'observations.read'
    when 'observations.record' then 'observations.record'
    when 'onboarding.complete' then 'onboarding.complete'
    when 'onboarding.read' then 'onboarding.read'
    when 'option-sets.manage' then 'option_sets.manage'
    when 'option-sets.read' then 'option_sets.read'
    when 'orders.manage' then 'orders.manage'
    when 'orders.overrideCredit' then 'orders.override_credit'
    when 'orders.prepare' then 'orders.prepare'
    when 'orders.read' then 'orders.read'
    when 'organizations.delete' then 'organization.delete'
    when 'organizations.listMembers' then 'members.read'
    when 'organizations.removeMember' then 'members.remove'
    when 'organizations.suspendMember' then 'members.remove'
    when 'organizations.transferOwnership' then 'organization.transfer_ownership'
    when 'organizations.update' then 'organization.update'
    when 'organizations.updateRole' then 'members.update_role'
    when 'passes.checkIn' then 'passes.check_in'
    when 'passes.manage' then 'passes.manage'
    when 'passes.read' then 'passes.read'
    when 'payroll-export.export' then 'payroll_export.export'
    when 'payroll-export.read' then 'payroll_export.read'
    when 'periods.manage' then 'periods.manage'
    when 'periods.read' then 'periods.read'
    when 'periods.write' then 'periods.write'
    when 'permissions.listRoles' then 'members.read'
    when 'permissions.setOverride' then 'roles.manage'
    when 'pipelines.manage' then 'pipelines.manage'
    when 'pipelines.read' then 'pipelines.read'
    when 'posts.manage' then 'posts.manage'
    when 'posts.moderate' then 'posts.moderate'
    when 'posts.read' then 'posts.read'
    when 'posts.write' then 'posts.write'
    when 'promotions.manage' then 'promotions.manage'
    when 'promotions.read' then 'promotions.read'
    when 'qualifications.grant' then 'qualifications.grant'
    when 'qualifications.manage' then 'qualifications.manage'
    when 'qualifications.read' then 'qualifications.read'
    when 'quotes.manage' then 'quotes.manage'
    when 'quotes.read' then 'quotes.read'
    when 'quotes.write' then 'quotes.write'
    when 'reactions.create' then 'reactions.create'
    when 'reactions.manage' then 'reactions.manage'
    when 'reactions.read' then 'reactions.read'
    when 'referrals.manage' then 'referrals.manage'
    when 'referrals.read' then 'referrals.read'
    when 'referrals.write' then 'referrals.write'
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
    when 'reviews.manage' then 'reviews.manage'
    when 'rfqs.manage' then 'rfqs.manage'
    when 'rfqs.read' then 'rfqs.read'
    when 'rfqs.write' then 'rfqs.write'
    when 'risks.assess' then 'risks.assess'
    when 'risks.manage' then 'risks.manage'
    when 'risks.read' then 'risks.read'
    when 'risks.write' then 'risks.write'
    when 'saved-views.read' then 'saved_views.read'
    when 'saved-views.share' then 'saved_views.share'
    when 'scores.compute' then 'scores.compute'
    when 'scores.manage' then 'scores.manage'
    when 'scores.read' then 'scores.read'
    when 'search.read' then 'search.read'
    when 'segments.read' then 'segments.read'
    when 'segments.write' then 'segments.write'
    when 'sequences.enroll' then 'sequences.enroll'
    when 'sequences.manage' then 'sequences.manage'
    when 'sequences.read' then 'sequences.read'
    when 'service-accounts.manage' then 'service_accounts.manage'
    when 'service-accounts.read' then 'service_accounts.read'
    when 'settings.platform' then 'settings.manage'
    when 'settings.read' then 'settings.read'
    when 'settings.update' then 'settings.update'
    when 'share-links.create' then 'share_links.create'
    when 'share-links.read' then 'share_links.read'
    when 'shifts.manage' then 'shifts.manage'
    when 'shifts.read' then 'shifts.read'
    when 'shifts.request' then 'shifts.request'
    when 'shifts.write' then 'shifts.write'
    when 'shipments.manage' then 'shipments.manage'
    when 'shipments.read' then 'shipments.read'
    when 'signatures.manage' then 'signatures.manage'
    when 'signatures.read' then 'signatures.read'
    when 'signatures.request' then 'signatures.request'
    when 'sla.manage' then 'sla.manage'
    when 'sla.read' then 'sla.read'
    when 'sso.manage' then 'sso.manage'
    when 'subjects.manage' then 'subjects.manage'
    when 'tags.apply' then 'tags.apply'
    when 'tags.manage' then 'tags.manage'
    when 'tags.read' then 'tags.read'
    when 'tasks.manage' then 'tasks.manage'
    when 'tasks.read' then 'tasks.read'
    when 'tasks.write' then 'tasks.write'
    when 'tax.manage' then 'tax.manage'
    when 'tax.read' then 'tax.read'
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
    when 'tills.manage' then 'tills.manage'
    when 'tills.read' then 'tills.read'
    when 'tills.write' then 'tills.write'
    when 'time-entries.approve' then 'time_entries.approve'
    when 'time-entries.manage' then 'time_entries.manage'
    when 'time-entries.read' then 'time_entries.read'
    when 'time-entries.track' then 'time_entries.track'
    when 'timeline.read' then 'timeline.read'
    when 'trash.create' then 'trash.create'
    when 'trash.manage' then 'trash.manage'
    when 'trash.read' then 'trash.read'
    when 'trash.restore' then 'trash.restore'
    when 'usage.read' then 'usage.read'
    when 'usage.record' then 'usage.record'
    when 'versions.create' then 'versions.create'
    when 'versions.manage' then 'versions.manage'
    when 'versions.read' then 'versions.read'
    when 'versions.restore' then 'versions.restore'
    when 'waitlist.invite' then 'waitlist.invite'
    when 'waitlist.manage' then 'waitlist.manage'
    when 'warehouse.manage' then 'warehouse.manage'
    when 'warehouse.pick' then 'warehouse.pick'
    when 'warehouse.read' then 'warehouse.read'
    when 'warranty.decide' then 'warranty.decide'
    when 'warranty.read' then 'warranty.read'
    when 'warranty.write' then 'warranty.write'
    when 'webhooks.manage' then 'webhooks.manage'
    when 'webhooks.read' then 'webhooks.read'
    when 'workflow-editor.manage' then 'workflow_editor.manage'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflow-editor.write' then 'workflow_editor.write'
    when 'workflows.manage' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prorate_change (
  subscription_id uuid,
  unit_amount     bigint                   DEFAULT NULL::bigint,
  quantity        integer                  DEFAULT NULL::integer,
  at              timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."billing_native_subscriptions"%rowtype;
  v_at timestamptz := coalesce(prorate_change.at, now());
  v_fraction numeric;
  v_credit bigint;
  v_charge bigint;
  v_net bigint;
  v_new_amount bigint;
  v_new_quantity integer;
  v_tx uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the service role prorates subscription changes' using errcode = '42501', hint = 'BILLING_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."billing_native_subscriptions" x where x."id" = prorate_change.subscription_id for update;
  if not found or v_row."status" <> 'active' then
    raise exception 'The subscription does not exist or is canceled' using errcode = 'P0002', hint = 'BILLING_SUBSCRIPTION_NOT_FOUND';
  end if;
  v_new_amount := coalesce(prorate_change.unit_amount, v_row."unit_amount");
  v_new_quantity := coalesce(prorate_change.quantity, v_row."quantity");
  if v_new_amount < 0 or v_new_quantity < 0 then
    raise exception 'The new price or quantity is negative' using errcode = '22023', hint = 'BILLING_SUBSCRIPTION_INVALID';
  end if;
  v_fraction := greatest(0, least(1,
    extract(epoch from v_row."period_ends_at" - v_at) / extract(epoch from v_row."period_ends_at" - v_row."period_starts_at")));
  v_credit := round(v_row."unit_amount" * v_row."quantity" * v_fraction);
  v_charge := round(v_new_amount * v_new_quantity * v_fraction);
  v_net := v_charge - v_credit;

  if v_net <> 0 then
    v_tx := "better_supabase"."ledger_post"(v_row."tenant_id", 'billing.proration',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable', 'billing:receivable:' || v_row."currency", 'Subscription receivable ' || v_row."currency", v_row."currency", 0::smallint, null, null, null, true, null, 'billing', null), 'amount', v_net),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'revenue', 'billing:proration:' || v_row."currency", 'Subscription proration ' || v_row."currency", v_row."currency", 0::smallint, null, null, null, true, null, 'billing', null), 'amount', -v_net)),
      'billing-native-subscriptions', v_row."id"::text,
      'Proration for ' || v_row."plan",
      'billing.proration:' || v_row."id"::text || ':' || extract(epoch from v_at)::text,
      v_at,
      jsonb_build_object('plan', v_row."plan", 'credit', v_credit, 'charge', v_charge));
  end if;
  update "better_supabase"."billing_native_subscriptions" set "unit_amount" = v_new_amount, "quantity" = v_new_quantity
    where "id" = v_row."id";
  return jsonb_build_object('subscription_id', v_row."id", 'credit', v_credit::text, 'charge', v_charge::text, 'net', v_net::text,
    'currency', v_row."currency", 'transaction_id', v_tx);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_marketplace_invoice (
  configuration_id text,
  external_id      text,
  state            text,
  period_start     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  period_end       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  total            numeric                  DEFAULT NULL::numeric,
  currency         text                     DEFAULT NULL::text,
  items            jsonb                    DEFAULT NULL::jsonb,
  event_at         timestamp with time zone DEFAULT now()
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_invoices";
  v_before text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_invoice.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  select y."state" into v_before from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  insert into "better_supabase"."marketplace_invoices" ("installation_id", "external_id", "state", "period_starts_at", "period_ends_at", "total", "currency", "items", "event_at")
  values (v_installation, record_marketplace_invoice.external_id, record_marketplace_invoice.state, record_marketplace_invoice.period_start, record_marketplace_invoice.period_end, coalesce(record_marketplace_invoice.total, 0), coalesce(record_marketplace_invoice.currency, 'usd'), coalesce(record_marketplace_invoice.items, '[]'::jsonb), coalesce(record_marketplace_invoice.event_at, now()))
  on conflict ("installation_id", "external_id") do update set
    "state" = excluded."state",
    "period_starts_at" = coalesce(excluded."period_starts_at", "better_supabase"."marketplace_invoices"."period_starts_at"),
    "period_ends_at" = coalesce(excluded."period_ends_at", "better_supabase"."marketplace_invoices"."period_ends_at"),
    "total" = case when record_marketplace_invoice.total is null then "better_supabase"."marketplace_invoices"."total" else excluded."total" end,
    "currency" = case when record_marketplace_invoice.currency is null then "better_supabase"."marketplace_invoices"."currency" else excluded."currency" end,
    "items" = case when record_marketplace_invoice.items is null then "better_supabase"."marketplace_invoices"."items" else excluded."items" end,
    "event_at" = excluded."event_at"
  where "better_supabase"."marketplace_invoices"."event_at" <= excluded."event_at"
  returning * into v_row;
  if v_row."id" is null then
    select y.* into v_row from "better_supabase"."marketplace_invoices" y where y."installation_id" = v_installation and y."external_id" = record_marketplace_invoice.external_id;
  elsif v_before is distinct from v_row."state" then
    perform "better_supabase".emit_event('marketplace_invoice.status_changed', jsonb_build_object('installationId', v_installation, 'invoiceId', v_row."id", 'externalId', v_row."external_id", 'state', v_row."state"), 'marketplace-invoices/' || v_row."id", null, null, 'better-supabase/vercel-marketplace');
  perform better_supabase.audit_event(
    event_type => 'marketplace_invoice.status_changed',
    category => 'billing',
    target_type => 'marketplace_invoice',
    record_id => v_row."id"::text,
    metadata => jsonb_build_object('installationId', v_installation, 'invoiceId', v_row."id", 'externalId', v_row."external_id", 'state', v_row."state")
  );
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_marketplace_meter_report (
  configuration_id     text,
  meter_id             text,
  period_start         timestamp with time zone,
  period_end           timestamp with time zone,
  quantity             numeric,
  resource_external_id text                     DEFAULT ''::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_installation uuid;
  v_row "better_supabase"."marketplace_meter_reports";
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  select x."id" into v_installation from "better_supabase"."marketplace_installations" x where x."configuration_id" = record_marketplace_meter_report.configuration_id;
  if v_installation is null then
    raise exception 'No installation has this configuration id' using errcode = 'P0002', hint = 'MARKETPLACE_INSTALLATION_NOT_FOUND';
  end if;
  insert into "better_supabase"."marketplace_meter_reports" ("installation_id", "resource_external_id", "meter_id", "period_starts_at", "period_ends_at", "quantity")
  values (v_installation, coalesce(record_marketplace_meter_report.resource_external_id, ''), record_marketplace_meter_report.meter_id, record_marketplace_meter_report.period_start, record_marketplace_meter_report.period_end, record_marketplace_meter_report.quantity)
  on conflict ("installation_id", "resource_external_id", "meter_id", "period_starts_at", "period_ends_at") do update set
    "quantity" = excluded."quantity",
    "reported_at" = case when "better_supabase"."marketplace_meter_reports"."quantity" = excluded."quantity" then "better_supabase"."marketplace_meter_reports"."reported_at" end
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_support_session (
  target      uuid,
  reason      text    DEFAULT NULL::text,
  read_only   boolean DEFAULT true,
  metadata    jsonb   DEFAULT '{}'::jsonb,
  tenant      uuid    DEFAULT NULL::uuid,
  admin_id    uuid    DEFAULT NULL::uuid,
  approved_by uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  new_id uuid;
  requested jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin) or approved_by is not null
      or not "better_supabase"."is_platform"('impersonation.start') then
      raise exception 'Not allowed to ask for a support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'IMPERSONATION_SELF';
  end if;
  if approved_by = admin then
    raise exception 'An admin cannot approve their own support session' using errcode = '42501', hint = 'IMPERSONATION_SELF_APPROVAL';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'IMPERSONATION_TARGET_MISSING';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'IMPERSONATION_REASON_REQUIRED';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (blocks.impersonation.options.allowWrites)' using errcode = '42501', hint = 'IMPERSONATION_WRITES_DISABLED';
  end if;
  insert into "better_supabase"."support_requests" ("admin_id", "target_id", "reason", "tenant_id", "read_only", "metadata", "expires_at", "approved_by", "approved_at")
  values (admin, target, coalesce(btrim(reason), ''), tenant, coalesce(read_only, true), coalesce(metadata, '{}'),
    now() + '1 hour'::interval, approved_by, case when approved_by is null then null else now() end)
  returning "id" into new_id;
  if tenant is not null and approved_by is null then
    perform "better_supabase"."open_approval"(
      tenant, 'support_request', new_id::text, 'start', jsonb_build_object('steps', '[{"approvers": {}, "required": 1}]'::jsonb, 'selfApproval', false, 'expiresIn', '1 hour', 'run', null), coalesce(btrim(reason), ''),
      jsonb_build_object('adminId', admin, 'targetUserId', target, 'readOnly', coalesce(read_only, true))
    );
  end if;
  select jsonb_build_object(
    'id', x."id",
    'admin_id', x."admin_id",
    'target_user_id', x."target_id",
    'reason', x."reason",
    'tenant', x."tenant_id",
    'read_only', x."read_only",
    'metadata', x."metadata",
    'requested_at', x."requested_at",
    'expires_at', x."expires_at",
    'approved_by', x."approved_by",
    'approved_at', x."approved_at",
    'session_id', x."session_id"
  ) into requested from "better_supabase"."support_requests" x where x."id" = new_id;
  return requested;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_field_key (
  owner text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_secret uuid;
  v_old text;
  v_new text;
  v_rows bigint;
  v_values bigint := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if rotate_field_key.owner is null or length(rotate_field_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  if not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))
    or case when rotate_field_key.owner like 'tenant:%' then coalesce(better_supabase.can('tenant', (substr(rotate_field_key.owner, 8))::uuid, 'field_encryption.manage'), false) else false end, false) then
    raise exception 'not allowed to rotate the field key of this owner' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  lock table "public"."client_notes", "better_supabase"."field_values" in exclusive mode;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-key:' || rotate_field_key.owner, 0));
  select ds.id, ds.decrypted_secret into v_secret, v_old from vault.decrypted_secrets ds
  where ds.name = 'bs:field-key:' || rotate_field_key.owner;
  if v_secret is null then
    raise exception 'the owner has no field key' using errcode = 'P0002', hint = 'FIELD_KEY_NOT_FOUND';
  end if;
  v_new := encode(extensions.gen_random_bytes(32), 'base64');
  perform vault.update_secret(v_secret, v_new);
  update "public"."client_notes" x set "diagnosis" = case when left(x."diagnosis", 5) = 'bsf1:' then "better_supabase"."field_seal"(v_new, "better_supabase"."field_open"(v_old, x."diagnosis")) else x."diagnosis" end, "birth_date" = case when left(x."birth_date", 5) = 'bsf1:' then "better_supabase"."field_seal"(v_new, "better_supabase"."field_open"(v_old, x."birth_date")) else x."birth_date" end
  where 'tenant:' || (x."organization_id")::text = rotate_field_key.owner and (left(x."diagnosis", 5) = 'bsf1:' or left(x."birth_date", 5) = 'bsf1:');
  get diagnostics v_rows = row_count;
  v_values := v_values + v_rows;
  update "better_supabase"."field_values" x set "value_text" = case when left(x."value_text", 5) = 'bsf1:' then "better_supabase"."field_seal"(v_new, "better_supabase"."field_open"(v_old, x."value_text")) else x."value_text" end
  where 'tenant:' || (x."tenant_id")::text = rotate_field_key.owner and (left(x."value_text", 5) = 'bsf1:');
  get diagnostics v_rows = row_count;
  v_values := v_values + v_rows;
  perform "better_supabase".emit_event('field_key.rotated', jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values), 'field-keys/' || rotate_field_key.owner, null, null, 'better-supabase/field-encryption');
  perform better_supabase.audit_event(
    event_type => 'field_key.rotated',
    category => 'security',
    target_type => 'field_key',
    record_id => rotate_field_key.owner,
    metadata => jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values)
  );
  return jsonb_build_object('owner', rotate_field_key.owner, 'values', v_values, 'rotated_at', now());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_support_session (
  target    uuid,
  reason    text     DEFAULT NULL::text,
  ttl       interval DEFAULT '00:30:00'::interval,
  read_only boolean  DEFAULT true,
  metadata  jsonb    DEFAULT '{}'::jsonb,
  tenant    uuid     DEFAULT NULL::uuid,
  admin_id  uuid     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  admin uuid;
  session_id uuid;
  started jsonb;
  approval_id uuid;
  approver uuid;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not "better_supabase"."is_platform"('impersonation.start') then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'IMPERSONATION_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'IMPERSONATION_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'IMPERSONATION_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > '4 hours'::interval then
    raise exception 'ttl must be between 0 and %', '4 hours' using errcode = '22023', hint = 'IMPERSONATION_TTL';
  end if;
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if (exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> 'platform_permissions') = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> 'platform_permissions') > 0
  ) or exists (
    select 1 from "better_supabase"."platform_roles" a
    where a."user_id" = target
  )) then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'IMPERSONATION_TARGET_PLATFORM';
  end if;
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (blocks.impersonation.options.allowWrites)' using errcode = '42501', hint = 'IMPERSONATION_WRITES_DISABLED';
  end if;
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'IMPERSONATION_REASON_REQUIRED';
  end if;
  -- A second admin approved this start: the approval is consumed below.
  select x."id", x."approved_by" into approval_id, approver
  from "better_supabase"."support_requests" x
  where x."admin_id" = admin
    and x."target_id" = target
    and x."tenant_id" is not distinct from tenant
    and (not x."read_only" or coalesce(read_only, true))
    and x."approved_by" is not null
    and x."approved_by" <> admin
    and x."session_id" is null
    and x."expires_at" > now()
  order by x."approved_at" desc
  limit 1
  for update;
  if approval_id is null then
    raise exception 'A second admin must approve this support session (approve_support_request)' using errcode = '42501', hint = 'IMPERSONATION_APPROVAL_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_support_start"(uuid, uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using admin, target, reason, metadata;
    end if;
  end;
  update "better_supabase"."support_sessions" s set "ended_at" = now(), "ended_by" = 'admin'
  where s."admin_id" = admin and s."ended_at" is null;
  insert into "better_supabase"."support_sessions" ("admin_id", "target_id", "reason", "tenant_id", "read_only", "expires_at", "metadata")
  values (admin, target, coalesce(reason, ''), tenant, read_only, now() + ttl, coalesce(metadata, '{}'))
  returning "id" into session_id;
  update "better_supabase"."support_requests" x set "session_id" = session_id where x."id" = approval_id;
  select jsonb_build_object(
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
  ) into started from "better_supabase"."support_sessions" s where s."id" = session_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_support_start"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using session_id;
    end if;
  end;
  perform "better_supabase".emit_event('support_session.started', jsonb_build_object('sessionId', started ->> 'id', 'adminId', started ->> 'admin_id', 'targetUserId', started ->> 'target_user_id', 'reason', started ->> 'reason', 'readOnly', (started ->> 'read_only')::boolean, 'expiresAt', started ->> 'expires_at', 'organizationId', started ->> 'tenant'), 'support-sessions/' || session_id, (tenant)::text, 'support_session.started:' || session_id, 'better-supabase/impersonation');
  perform better_supabase.audit_event(
    event_type => 'support_session.started',
    category => 'security',
    target_type => 'user',
    record_id => target::text,
    tenant => (tenant)::uuid,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only, 'request_id', approval_id, 'approved_by', approver),
    idempotency_key => 'support_session.started:' || session_id,
    actor_id => admin,
    support_session => session_id,
    impersonated_by => admin,
    impersonation_reason => reason
  );
  return started;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.support_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'admin_id', x."admin_id",
    'target_user_id', x."target_id",
    'reason', x."reason",
    'tenant', x."tenant_id",
    'read_only', x."read_only",
    'metadata', x."metadata",
    'requested_at', x."requested_at",
    'expires_at', x."expires_at",
    'approved_by', x."approved_by",
    'approved_at', x."approved_at",
    'session_id', x."session_id"
  )
  from "better_supabase"."support_requests" x
  where x."id" = $1
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or x."admin_id" = auth.uid() or "better_supabase"."is_platform"('impersonation.start'))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unreported_marketplace_meter_reports (
  configuration_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role manages Marketplace installations' using errcode = '42501', hint = 'MARKETPLACE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x."period_starts_at", x."meter_id"), '[]'::jsonb)
    from "better_supabase"."marketplace_meter_reports" x join "better_supabase"."marketplace_installations" y on y."id" = x."installation_id"
    where y."configuration_id" = unreported_marketplace_meter_reports.configuration_id and x."reported_at" is null
  );
end;
$function$;

ALTER TABLE "better_supabase"."support_requests"
  ADD CONSTRAINT "support_requests_target_id_fkey" FOREIGN KEY (target_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."support_sessions"
  ADD CONSTRAINT "support_sessions_target_id_fkey" FOREIGN KEY (target_id) REFERENCES auth.users(id) ON DELETE SET NULL;

REVOKE ALL ON FUNCTION "api"."rotate_field_key"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rotate_field_key"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rotate_field_key"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rotate_field_key"(text) TO "authenticated", "service_role";
