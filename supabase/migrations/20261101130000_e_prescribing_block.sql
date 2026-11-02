SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."prescriptions" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"         uuid                     NOT NULL,
  "order_id"          uuid                     NOT NULL,
  "subject_type"      text                     NOT NULL,
  "subject_id"        text                     NOT NULL,
  "prescriber_id"     uuid                     NOT NULL,
  "prescriber_name"   text,
  "status"            text                     NOT NULL DEFAULT 'draft'::text,
  "snapshot"          jsonb,
  "signed_by"         uuid,
  "signed_at"         timestamp with time zone,
  "gateway"           text,
  "gateway_reference" text,
  "sent_at"           timestamp with time zone,
  "delivery_error"    text,
  "dispensed_at"      timestamp with time zone,
  "cancelled_at"      timestamp with time zone,
  "cancel_reason"     text,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "prescriptions_cancel_reason_check" CHECK (((cancel_reason IS NULL) OR (length(cancel_reason) <= 1000))),
  CONSTRAINT "prescriptions_check1" CHECK (((signed_by IS NULL) OR (signed_by = prescriber_id))),
  CONSTRAINT "prescriptions_check2" CHECK (((status <> ALL (ARRAY['sent'::text, 'dispensed'::text])) OR ((sent_at IS NOT NULL) AND (gateway IS NOT NULL)))),
  CONSTRAINT "prescriptions_check3" CHECK (((status <> 'dispensed'::text) OR (dispensed_at IS NOT NULL))),
  CONSTRAINT "prescriptions_check4" CHECK (((status <> 'cancelled'::text) OR (cancelled_at IS NOT NULL))),
  CONSTRAINT "prescriptions_check" CHECK (((status = ANY (ARRAY['draft'::text, 'cancelled'::text])) OR ((signed_by IS NOT NULL) AND (signed_at IS NOT NULL) AND (snapshot IS
    NOT NULL)))),
  CONSTRAINT "prescriptions_delivery_error_check" CHECK (((delivery_error IS NULL) OR (length(delivery_error) <= 1000))),
  CONSTRAINT "prescriptions_gateway_check" CHECK (((gateway IS NULL) OR ((length(gateway) >= 1) AND (length(gateway) <= 100)))),
  CONSTRAINT "prescriptions_gateway_reference_check" CHECK (((gateway_reference IS NULL) OR (length(gateway_reference) <= 200))),
  CONSTRAINT "prescriptions_pkey" PRIMARY KEY (id),
  CONSTRAINT "prescriptions_prescriber_name_check" CHECK (((prescriber_name IS NULL) OR (length(prescriber_name) <= 300))),
  CONSTRAINT "prescriptions_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'signed'::text, 'sent'::text, 'dispensed'::text, 'cancelled'::text])))
);

ALTER TABLE "better_supabase"."prescriptions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.cancel_prescription (
  prescription_id uuid,
  reason          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."cancel_prescription"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.create_prescription (
  tenant   uuid,
  order_id uuid,
  attrs    jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_prescription"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_prescription (
  prescription_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_prescription"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_prescriptions (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_prescriptions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_prescription_delivery (
  prescription_id uuid,
  gateway         text,
  reference       text DEFAULT NULL::text,
  error           text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_prescription_delivery"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.record_prescription_dispense (
  prescription_id uuid,
  dispensed_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_prescription_dispense"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.sign_prescription (
  prescription_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."sign_prescription"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_prescription (
  prescription_id uuid,
  reason          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_reason text := nullif(trim(cancel_prescription.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = cancel_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.manage'), false))) and not ((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) and v_row."prescriber_id" is not distinct from auth.uid()) then
    raise exception 'only the prescriber or a manager cancels a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" in ('dispensed', 'cancelled') then
    raise exception 'a dispensed or cancelled prescription cannot be cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_reason is null and v_row."status" <> 'draft' then
    raise exception 'cancelling a signed or sent prescription needs a reason' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reason, '')) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'cancelled', "cancelled_at" = now(), "cancel_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('prescription.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.cancelled',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription cancelled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_prescription (
  tenant   uuid,
  order_id uuid,
  attrs    jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_attrs jsonb := coalesce(create_prescription.attrs, '{}'::jsonb);
  v_order "better_supabase"."medication_orders";
  v_row "better_supabase"."prescriptions";
  v_prescriber uuid := auth.uid();
  v_name text := nullif(trim(v_attrs ->> 'prescriberName'), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_prescription.tenant is not null and coalesce(better_supabase.can('tenant', create_prescription.tenant, 'e_prescribing.write'), false))) then
    raise exception 'not allowed to draft prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  begin
    v_prescriber := coalesce(v_prescriber, nullif(v_attrs ->> 'prescriberId', '')::uuid);
  exception when invalid_text_representation then
    raise exception 'prescriberId is a uuid' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end;
  if v_prescriber is null then
    raise exception 'a prescription needs a prescriber' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_name is not null and length(v_name) > 300 then
    raise exception 'a prescriber name is up to 300 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = create_prescription.tenant and x."id" = create_prescription.order_id;
  if not found then
    raise exception 'the order is not one of the organization' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'only an active medication order can be prescribed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  begin
    insert into "better_supabase"."prescriptions" ("tenant_id", "order_id", "subject_type", "subject_id", "prescriber_id", "prescriber_name")
    values (create_prescription.tenant, v_order."id", v_order."subject_type", v_order."subject_id", v_prescriber, v_name)
    returning * into v_row;
  exception when unique_violation then
    raise exception 'this order already has a prescription that is not cancelled' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end;
  perform "better_supabase".emit_event('prescription.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.created',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription drafted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_tables()
  RETURNS TABLE (
    subject  text,
    name     text,
    tbl      text,
    col      text,
    purge    boolean,
    omit     text[],
    exported boolean
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select t.subject, t.name, t.tbl, t.col, t.purge,
    t.omit || array(
      select a.attname::text
      from pg_catalog.pg_attribute a
      where a.attrelid = to_regclass(t.tbl)
        and a.attnum > 0
        and not a.attisdropped
        and a.attname ~* 'token|secret|_hash|password|api_key|license_key'
        and a.attname <> t.col
        and not a.attname = any(t.omit)
      order by a.attnum
    ) as omit,
    t.exported
  from (
  select * from (values
    ('user', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'actor_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('user', 'public.memberships', '"public"."memberships"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.platform_roles', '"better_supabase"."platform_roles"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.profiles', '"better_supabase"."profiles"', 'id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.notification_suppressions', '"better_supabase"."notification_suppressions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.user_settings', '"better_supabase"."user_settings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.guests', '"better_supabase"."guests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.waitlist_entries', '"better_supabase"."waitlist_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.invite_code_redemptions', '"better_supabase"."invite_code_redemptions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.announcement_dismissals', '"better_supabase"."announcement_dismissals"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.streams', '"better_supabase"."streams"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.workflow_definition_grants', '"better_supabase"."workflow_definition_grants"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_members', '"better_supabase"."inbox_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_team_members', '"better_supabase"."inbox_team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_chat_participants', '"better_supabase"."ai_chat_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_messages', '"better_supabase"."ai_messages"', 'owner_id', true, array['search_tsv']::text[], true),
    ('user', 'better_supabase.ai_runs', '"better_supabase"."ai_runs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_tool_approvals', '"better_supabase"."ai_tool_approvals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_pending_inputs', '"better_supabase"."ai_pending_inputs"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_feedback', '"better_supabase"."ai_message_feedback"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chat_shares', '"better_supabase"."ai_chat_shares"', 'created_by', true, array['token_hash']::text[], true),
    ('user', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_run_steps', '"better_supabase"."ai_run_steps"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_harness_sessions', '"better_supabase"."ai_harness_sessions"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agents', '"better_supabase"."agents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.agent_ratings', '"better_supabase"."agent_ratings"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.connector_sessions', '"better_supabase"."connector_sessions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.push_devices', '"better_supabase"."push_devices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.teams', '"better_supabase"."teams"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.team_members', '"better_supabase"."team_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.signatures', '"better_supabase"."signatures"', 'signer', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.leases', '"better_supabase"."leases"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.courses', '"better_supabase"."courses"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.sequences', '"better_supabase"."sequences"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.posts', '"better_supabase"."posts"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'assessed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'subject_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'calibrated_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'assignee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'opened_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'counted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'prescriber_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.streams', '"better_supabase"."streams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_runs', '"better_supabase"."workflow_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_schedules', '"better_supabase"."workflow_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_start_requests', '"better_supabase"."workflow_start_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_definitions', '"better_supabase"."workflow_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_opt_outs', '"better_supabase"."workflow_opt_outs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'tenant_id', false, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.inboxes', '"better_supabase"."inboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_teams', '"better_supabase"."inbox_teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversation_events', '"better_supabase"."inbox_conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_deliveries', '"better_supabase"."inbox_message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_inbound_events', '"better_supabase"."inbox_inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.inbox_message_templates', '"better_supabase"."inbox_message_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scheduled_inbox_messages', '"better_supabase"."scheduled_inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_drafts', '"better_supabase"."inbox_drafts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'organization_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.number_sequences', '"better_supabase"."number_sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, array['token_hash', 'password_hash']::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_records', '"better_supabase"."import_records"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shared_views', '"better_supabase"."shared_views"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.relations', '"better_supabase"."relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.products', '"better_supabase"."products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_options', '"better_supabase"."product_options"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_option_values', '"better_supabase"."product_option_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variants', '"better_supabase"."product_variants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_values', '"better_supabase"."product_variant_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_price_lists', '"better_supabase"."catalog_price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_categories', '"better_supabase"."catalog_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_storefronts', '"better_supabase"."catalog_storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_identifiers', '"better_supabase"."product_identifiers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_relations', '"better_supabase"."product_relations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_items', '"better_supabase"."supplier_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.supplier_item_mappings', '"better_supabase"."supplier_item_mappings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_event_alarms', '"better_supabase"."calendar_event_alarms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_policies', '"better_supabase"."approval_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_suggestions', '"better_supabase"."document_suggestions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_transactions', '"better_supabase"."ledger_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_entries', '"better_supabase"."ledger_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_balances', '"better_supabase"."ledger_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ledger_holds', '"better_supabase"."ledger_holds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisitions', '"better_supabase"."purchase_requisitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_requisition_lines', '"better_supabase"."purchase_requisition_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipts', '"better_supabase"."inventory_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_receipt_lines', '"better_supabase"."inventory_receipt_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_shipping_rates', '"better_supabase"."order_shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillments', '"better_supabase"."order_fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_fulfillment_lines', '"better_supabase"."order_fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_returns', '"better_supabase"."order_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_return_lines', '"better_supabase"."order_return_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_refunds', '"better_supabase"."order_refunds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotions', '"better_supabase"."promotions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_codes', '"better_supabase"."promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_promotion_codes', '"better_supabase"."cart_promotion_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.promotion_redemptions', '"better_supabase"."promotion_redemptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forms', '"better_supabase"."forms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.form_answer_keys', '"better_supabase"."form_answer_keys"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signature_requests', '"better_supabase"."signature_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.signatures', '"better_supabase"."signatures"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedules', '"better_supabase"."template_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_schedule_runs', '"better_supabase"."template_schedule_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_kinds', '"better_supabase"."case_kinds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cases', '"better_supabase"."cases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.case_actions', '"better_supabase"."case_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.job_openings', '"better_supabase"."job_openings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipelines', '"better_supabase"."pipelines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stages', '"better_supabase"."pipeline_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_transitions', '"better_supabase"."pipeline_transitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.companies', '"better_supabase"."companies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.people', '"better_supabase"."people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.company_people', '"better_supabase"."company_people"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_depreciations', '"better_supabase"."asset_depreciations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.leases', '"better_supabase"."leases"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_charges', '"better_supabase"."lease_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_categories', '"better_supabase"."expense_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.expense_lines', '"better_supabase"."expense_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_funds', '"better_supabase"."donation_funds"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pledges', '"better_supabase"."pledges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donation_receipts', '"better_supabase"."donation_receipts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.donations', '"better_supabase"."donations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dispatch_route_stops', '"better_supabase"."dispatch_route_stops"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipments', '"better_supabase"."shipments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_packages', '"better_supabase"."shipment_packages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_tracking_events', '"better_supabase"."shipment_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipment_lines', '"better_supabase"."shipment_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.compliance_policies', '"better_supabase"."compliance_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_components', '"better_supabase"."incident_status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_component_history', '"better_supabase"."incident_status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortem_actions', '"better_supabase"."incident_postmortem_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_status_pages', '"better_supabase"."incident_status_pages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.courses', '"better_supabase"."courses"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_modules', '"better_supabase"."course_modules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lessons', '"better_supabase"."course_lessons"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_lesson_progress', '"better_supabase"."course_lesson_progress"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.course_certificates', '"better_supabase"."course_certificates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_summaries', '"better_supabase"."thread_summaries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.mail_threads', '"better_supabase"."mail_threads"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_messages', '"better_supabase"."mail_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracked_links', '"better_supabase"."mail_tracked_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_tracking_events', '"better_supabase"."mail_tracking_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segments', '"better_supabase"."segments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.segment_members', '"better_supabase"."segment_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queues', '"better_supabase"."assignment_queues"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrichments', '"better_supabase"."enrichments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshots', '"better_supabase"."forecast_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.forecast_snapshot_deals', '"better_supabase"."forecast_snapshot_deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_changes', '"better_supabase"."field_changes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sequences', '"better_supabase"."sequences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lead_score_checks', '"better_supabase"."lead_score_checks"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.post_boards', '"better_supabase"."post_boards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.posts', '"better_supabase"."posts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.content_entries', '"better_supabase"."content_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_types', '"better_supabase"."qualification_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualification_requirements', '"better_supabase"."qualification_requirements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.qualifications', '"better_supabase"."qualifications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_matrices', '"better_supabase"."risk_matrices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risks', '"better_supabase"."risks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.risk_assessments', '"better_supabase"."risk_assessments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_templates', '"better_supabase"."shift_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shifts', '"better_supabase"."shifts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_assignments', '"better_supabase"."shift_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_settings', '"better_supabase"."accounting_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_accounts', '"better_supabase"."accounting_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_account_roles', '"better_supabase"."accounting_account_roles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_journals', '"better_supabase"."accounting_journals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_periods', '"better_supabase"."accounting_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entries', '"better_supabase"."accounting_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_entry_lines', '"better_supabase"."accounting_entry_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimensions', '"better_supabase"."accounting_dimensions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_dimension_values', '"better_supabase"."accounting_dimension_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_fx_rates', '"better_supabase"."accounting_fx_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observation_definitions', '"better_supabase"."observation_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.observations', '"better_supabase"."observations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medications', '"better_supabase"."medications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_orders', '"better_supabase"."medication_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plans', '"better_supabase"."care_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_problems', '"better_supabase"."care_plan_problems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_goals', '"better_supabase"."care_plan_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_actions', '"better_supabase"."care_plan_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_programs', '"better_supabase"."inspection_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspections', '"better_supabase"."inspections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inspection_findings', '"better_supabase"."inspection_findings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.boms', '"better_supabase"."boms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_centers', '"better_supabase"."work_centers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_operations', '"better_supabase"."bom_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bom_components', '"better_supabase"."bom_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_orders', '"better_supabase"."production_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_order_operations', '"better_supabase"."production_order_operations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.production_consumptions', '"better_supabase"."production_consumptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_methods', '"better_supabase"."lims_methods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_goals', '"better_supabase"."appraisal_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lines', '"better_supabase"."pick_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.count_plans', '"better_supabase"."count_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_lines', '"better_supabase"."rfq_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_suppliers', '"better_supabase"."rfq_suppliers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quote_lines', '"better_supabase"."rfq_quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tills', '"better_supabase"."tills"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_rules', '"better_supabase"."care_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_prescription (
  prescription_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = get_prescription.prescription_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_prescriptions (
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
  v_filters jsonb := coalesce(list_prescriptions.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_prescriptions.tenant is not null and coalesce(better_supabase.can('tenant', list_prescriptions.tenant, 'e_prescribing.read'), false))) then
    raise exception 'not allowed to read prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_filters ->> 'status' is not null and v_filters ->> 'status' not in ('draft', 'signed', 'sent', 'dispensed', 'cancelled') then
    raise exception 'status is draft, signed, sent, dispensed or cancelled' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'orderId', q."order_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'prescriberId', q."prescriber_id", 'prescriberName', q."prescriber_name", 'status', q."status", 'order', q."snapshot", 'signedBy', q."signed_by", 'signedAt', q."signed_at", 'gateway', q."gateway", 'gatewayReference', q."gateway_reference", 'sentAt', q."sent_at", 'deliveryError', q."delivery_error", 'dispensedAt', q."dispensed_at", 'cancelledAt', q."cancelled_at", 'cancelReason', q."cancel_reason", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by q."created_at" desc, q."id")
    from (
      select y.* from "better_supabase"."prescriptions" y
      where y."tenant_id" = list_prescriptions.tenant
        and (v_filters ->> 'orderId' is null or y."order_id" = (v_filters ->> 'orderId')::uuid)
        and (v_filters ->> 'subjectType' is null or y."subject_type" = v_filters ->> 'subjectType')
        and (v_filters ->> 'subjectId' is null or y."subject_id" = v_filters ->> 'subjectId')
        and (v_filters ->> 'status' is null or y."status" = v_filters ->> 'status')
        and (v_filters ->> 'prescriberId' is null or y."prescriber_id" = (v_filters ->> 'prescriberId')::uuid)
      order by y."created_at" desc, y."id"
      limit least(greatest(coalesce((v_filters ->> 'limit')::int, 50), 1), 200) offset greatest(coalesce((v_filters ->> 'offset')::int, 0), 0)
    ) q
  ), '[]'::jsonb);
end;
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
    when 'agents.create' then 'agents.write'
    when 'agents.moderate' then 'agents.moderate'
    when 'agents.publish' then 'agents.publish'
    when 'agents.read' then 'agents.read'
    when 'ai-chat.admin' then 'ai_chat.manage'
    when 'ai-chat.create' then 'ai_chat.create'
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
    when 'audit.revert' then 'audit.revert'
    when 'audit.view' then 'audit.read'
    when 'audit.viewAll' then 'audit.read'
    when 'automations.admin' then 'automations.manage'
    when 'automations.edit' then 'automations.write'
    when 'automations.publish' then 'automations.publish'
    when 'automations.read' then 'automations.read'
    when 'banking.import' then 'banking.import'
    when 'banking.manage' then 'banking.manage'
    when 'banking.read' then 'banking.read'
    when 'banking.reconcile' then 'banking.reconcile'
    when 'billable-time.invoice' then 'billable_time.invoice'
    when 'billable-time.manage' then 'billable_time.manage'
    when 'billable-time.read' then 'billable_time.read'
    when 'bookings.create' then 'bookings.create'
    when 'bookings.manage' then 'bookings.manage'
    when 'bookings.read' then 'bookings.read'
    when 'bulk.run' then 'bulk.run'
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
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
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
    when 'employees.viewSensitive' then 'employees.read_sensitive'
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
    when 'imports.manage' then 'imports.manage'
    when 'inbox.assign' then 'inbox.assign'
    when 'inbox.manage' then 'inbox.manage'
    when 'inbox.read' then 'inbox.read'
    when 'inbox.reply' then 'inbox.reply'
    when 'incidents.manage' then 'incidents.manage'
    when 'incidents.read' then 'incidents.read'
    when 'incidents.write' then 'incidents.write'
    when 'inspections.manage' then 'inspections.manage'
    when 'inspections.read' then 'inspections.read'
    when 'inspections.write' then 'inspections.write'
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.approve' then 'invoices.approve'
    when 'invoices.collect' then 'invoices.collect'
    when 'invoices.manage' then 'invoices.manage'
    when 'invoices.overrideMatch' then 'invoices.override_match'
    when 'invoices.purchase' then 'invoices.purchase'
    when 'invoices.read' then 'invoices.read'
    when 'invoices.write' then 'invoices.write'
    when 'knowledge.manage' then 'knowledge.manage'
    when 'knowledge.read' then 'knowledge.read'
    when 'knowledge.write' then 'knowledge.write'
    when 'leases.maintain' then 'leases.maintain'
    when 'leases.manage' then 'leases.manage'
    when 'leases.read' then 'leases.read'
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
    when 'relations.manage' then 'relations.manage'
    when 'relations.read' then 'relations.read'
    when 'reminders.manage' then 'reminders.manage'
    when 'reminders.read' then 'reminders.read'
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
    when 'segments.edit' then 'segments.write'
    when 'segments.read' then 'segments.read'
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
    when 'time-tracking.approve' then 'time_tracking.approve'
    when 'time-tracking.manage' then 'time_tracking.manage'
    when 'time-tracking.read' then 'time_tracking.read'
    when 'time-tracking.track' then 'time_tracking.track'
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
    when 'webhooks-out.manage' then 'webhooks.manage'
    when 'webhooks-out.view' then 'webhooks.read'
    when 'workflow-editor.admin' then 'workflow_editor.manage'
    when 'workflow-editor.edit' then 'workflow_editor.write'
    when 'workflow-editor.publish' then 'workflow_editor.publish'
    when 'workflow-editor.read' then 'workflow_editor.read'
    when 'workflow-editor.run' then 'workflow_editor.run'
    when 'workflows.admin' then 'workflows.manage'
    when 'workflows.read' then 'workflows.read'
    when 'workflows.run' then 'workflows.run'
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prescription_order_snapshot (
  tenant   uuid,
  order_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'orderId', x."id", 'medicationId', x."medication_id", 'medicationName', mx."name",
    'codeSystem', mx."code_system", 'code', mx."code", 'dose', x."dose", 'doseUnit', x."dose_unit",
    'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed",
    'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day",
    'startsOn', x."starts_on", 'endsOn', x."ends_on")
  from "better_supabase"."medication_orders" x join "better_supabase"."medications" mx on mx."tenant_id" = x."tenant_id" and mx."id" = x."medication_id"
  where x."tenant_id" = prescription_order_snapshot.tenant and x."id" = prescription_order_snapshot.order_id;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_prescription_delivery (
  prescription_id uuid,
  gateway         text,
  reference       text DEFAULT NULL::text,
  error           text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_gateway text := nullif(trim(record_prescription_delivery.gateway), '');
  v_reference text := nullif(trim(record_prescription_delivery.reference), '');
  v_error text := nullif(trim(record_prescription_delivery.error), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_delivery.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to send prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_gateway is null or length(v_gateway) > 100 then
    raise exception 'gateway is 1 to 100 characters' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if length(coalesce(v_reference, '')) > 200 or length(coalesce(v_error, '')) > 1000 then
    raise exception 'a reference is up to 200 characters and an error up to 1000' using errcode = '22023', hint = 'PRESCRIPTION_INVALID';
  end if;
  if v_row."status" <> 'signed' then
    raise exception 'only a signed prescription can be sent' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  if v_error is not null then
    update "better_supabase"."prescriptions" x set "gateway" = v_gateway, "delivery_error" = v_error, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('prescription.delivery_failed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.delivery_failed',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription delivery failed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  else
    update "better_supabase"."prescriptions" x set "status" = 'sent', "gateway" = v_gateway, "gateway_reference" = v_reference,
      "sent_at" = now(), "delivery_error" = null, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('prescription.sent', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.sent',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription sent',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_prescription_dispense (
  prescription_id uuid,
  dispensed_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = record_prescription_dispense.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.write'), false))) then
    raise exception 'not allowed to record dispensing' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'sent' then
    raise exception 'only a sent prescription can be dispensed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  update "better_supabase"."prescriptions" x set "status" = 'dispensed', "dispensed_at" = coalesce(record_prescription_dispense.dispensed_at, now()), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('prescription.dispensed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.dispensed',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription dispensed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_subject_export (
  subject_type text,
  subject_id   text,
  format       text DEFAULT 'ndjson'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."data_exports";
  v_tenant uuid;
  v_record jsonb;
  v_name text;
  v_reveal text;
  v_reveal_schema text;
  v_proc text;
  v_arg text;
  v_sealed text[];
  v_plain jsonb;
  v_rows jsonb;
  v_fields jsonb;
  v_parts jsonb := '{}'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_subject_export.format is null or request_subject_export.format not in ('ndjson', 'csv') then
    raise exception 'format must be ndjson or csv' using errcode = '22023', hint = 'DATA_EXPORT_FORMAT';
  end if;
  case request_subject_export.subject_type
    when 'message' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."messages" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.messages';
      v_reveal := 'messages_reveal';
      v_reveal_schema := 'better_supabase';
    when 'conversation' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."conversations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.conversations';
      v_reveal := 'conversations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'channel' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."channels" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.channels';
      v_reveal := 'channels_reveal';
      v_reveal_schema := 'better_supabase';
    when 'company' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."companies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.companies';
      v_reveal := 'companies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'person' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."people" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.people';
      v_reveal := 'people_reveal';
      v_reveal_schema := 'better_supabase';
    when 'deal' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."deals" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.deals';
      v_reveal := 'deals_reveal';
      v_reveal_schema := 'better_supabase';
    when 'course' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."courses" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.courses';
      v_reveal := 'courses_reveal';
      v_reveal_schema := 'better_supabase';
    when 'post' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."posts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.posts';
      v_reveal := 'posts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'activity' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."activities" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.activities';
      v_reveal := 'activities_reveal';
      v_reveal_schema := 'better_supabase';
    when 'quote' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."quotes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.quotes';
      v_reveal := 'quotes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_item' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_items" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_items';
      v_reveal := 'work_items_reveal';
      v_reveal_schema := 'better_supabase';
    when 'employee' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."employees" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.employees';
      v_reveal := 'employees_reveal';
      v_reveal_schema := 'better_supabase';
    when 'invoice' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."invoices" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.invoices';
      v_reveal := 'invoices_reveal';
      v_reveal_schema := 'better_supabase';
    when 'ledger_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."ledger_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.ledger_accounts';
      v_reveal := 'ledger_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."products" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.products';
      v_reveal := 'products_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product_variant' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."product_variants" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.product_variants';
      v_reveal := 'product_variants_reveal';
      v_reveal_schema := 'better_supabase';
    when 'rfq' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."rfqs" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.rfqs';
      v_reveal := 'rfqs_reveal';
      v_reveal_schema := 'better_supabase';
    when 'till' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."tills" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.tills';
      v_reveal := 'tills_reveal';
      v_reveal_schema := 'better_supabase';
    when 'order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.orders';
      v_reveal := 'orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'calendar_event' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."calendar_events" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.calendar_events';
      v_reveal := 'calendar_events_reveal';
      v_reveal_schema := 'better_supabase';
    when 'booking' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bookings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bookings';
      v_reveal := 'bookings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."assets" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.assets';
      v_reveal := 'assets_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset_location' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."asset_locations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.asset_locations';
      v_reveal := 'asset_locations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'lease' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."leases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.leases';
      v_reveal := 'leases_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_report' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_reports" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_reports';
      v_reveal := 'expense_reports_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_line' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_lines" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_lines';
      v_reveal := 'expense_lines_reveal';
      v_reveal_schema := 'better_supabase';
    when 'donation_fund' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."donation_funds" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.donation_funds';
      v_reveal := 'donation_funds_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_orders';
      v_reveal := 'work_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'shipment' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."shipments" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.shipments';
      v_reveal := 'shipments_reveal';
      v_reveal_schema := 'better_supabase';
    when 'contract' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."contracts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.contracts';
      v_reveal := 'contracts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'control' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."controls" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.controls';
      v_reveal := 'controls_reveal';
      v_reveal_schema := 'better_supabase';
    when 'compliance_policy' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."compliance_policies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.compliance_policies';
      v_reveal := 'compliance_policies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'qualification_type' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."qualification_types" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.qualification_types';
      v_reveal := 'qualification_types_reveal';
      v_reveal_schema := 'better_supabase';
    when 'risk' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."risks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.risks';
      v_reveal := 'risks_reveal';
      v_reveal_schema := 'better_supabase';
    when 'case' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."cases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.cases';
      v_reveal := 'cases_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspections" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspections';
      v_reveal := 'inspections_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_program' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_programs" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_programs';
      v_reveal := 'inspection_programs_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_finding' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_findings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_findings';
      v_reveal := 'inspection_findings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'form' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."forms" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.forms';
      v_reveal := 'forms_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meetings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meetings';
      v_reveal := 'meetings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting_decision' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meeting_decisions" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meeting_decisions';
      v_reveal := 'meeting_decisions_reveal';
      v_reveal_schema := 'better_supabase';
    when 'maintenance_plan' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."maintenance_plans" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.maintenance_plans';
      v_reveal := 'maintenance_plans_reveal';
      v_reveal_schema := 'better_supabase';
    when 'dam_usage_right' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."dam_usage_rights" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.dam_usage_rights';
      v_reveal := 'dam_usage_rights_reveal';
      v_reveal_schema := 'better_supabase';
    when 'lims_sample' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."lims_samples" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.lims_samples';
      v_reveal := 'lims_samples_reveal';
      v_reveal_schema := 'better_supabase';
    when 'tax_code' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."tax_codes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.tax_codes';
      v_reveal := 'tax_codes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'production_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."production_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.production_orders';
      v_reveal := 'production_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_center' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_centers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_centers';
      v_reveal := 'work_centers_reveal';
      v_reveal_schema := 'better_supabase';
    when 'bank_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bank_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bank_accounts';
      v_reveal := 'bank_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'care_plan' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."care_plans" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.care_plans';
      v_reveal := 'care_plans_reveal';
      v_reveal_schema := 'better_supabase';
    when 'incident' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."incidents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.incidents';
      v_reveal := 'incidents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'content_entry' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."content_entries" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.content_entries';
      v_reveal := 'content_entries_reveal';
      v_reveal_schema := 'better_supabase';
    when 'document' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."documents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.documents';
      v_reveal := 'documents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'customer' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."customers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.customers';
      v_reveal := 'customers_reveal';
      v_reveal_schema := 'public';
    when 'drive_node' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."drive_nodes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.drive_nodes';
      v_reveal := 'drive_nodes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'application' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."applications" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.applications';
      v_reveal := 'applications_reveal';
      v_reveal_schema := 'better_supabase';
    when 'change_request' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."change_requests" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.change_requests';
      v_reveal := 'change_requests_reveal';
      v_reveal_schema := 'public';
    when 'project' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."projects" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.projects';
      v_reveal := 'projects_reveal';
      v_reveal_schema := 'public';
    when 'task' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."tasks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.tasks';
      v_reveal := 'tasks_reveal';
      v_reveal_schema := 'public';
    else
      raise exception 'subject_type is not a record type in config.subjects' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end case;
  if v_record is null or not ((v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'data_lifecycle.export'), false))) then
    raise exception 'You may not export this record' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."data_exports" x
  where x."subject" = 'record' and x."subject_type" = request_subject_export.subject_type
    and x."subject_id" = request_subject_export.subject_id and x."requested_by" = auth.uid()
    and x."status" in ('pending', 'running');
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  -- Only the owner's reveal function, so one another role created never runs
  -- with this function's rights.
  select pg_catalog.format('%I.%I', n.nspname, p.proname), pg_catalog.format_type(p.proargtypes[0], null),
    array(select a.name from unnest(p.proargnames, p.proargmodes::text[]) with ordinality a(name, mode, n)
      where a.mode = 't' order by a.n offset 1)
  into v_proc, v_arg, v_sealed
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = v_reveal_schema and p.proname = v_reveal and p.pronargs = 1
    and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
  limit 1;
  -- The stored ciphertext never leaves: a caller the reveal returns no row
  -- for gets the record without its encrypted columns.
  if v_proc is not null then
    execute format('select to_jsonb(r.*) from %s(array[$1]::%s) r', v_proc, v_arg) into v_plain
    using request_subject_export.subject_id;
    v_record := (v_record - coalesce(v_sealed, '{}'::text[])) || coalesce(v_plain, '{}'::jsonb);
  end if;
  v_parts := jsonb_build_object(v_name, jsonb_build_array(v_record));
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_subscriptions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_subscriptions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."guest_grants" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.guest_grants', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."attachments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.attachments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."enrollments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.enrollments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_runs" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_runs', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_start_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_start_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."knowledge_documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.knowledge_documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."memories" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.memories', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."taggings" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.taggings', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_stages" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_stages', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_lifecycles" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_lifecycles', v_rows);
  end if;
  if v_tenant is not null then
    v_fields := coalesce("better_supabase"."read_field_values"(v_tenant, request_subject_export.subject_type, request_subject_export.subject_id), '[]'::jsonb);
    select coalesce(jsonb_agg(((to_jsonb(t.*)) || jsonb_build_object('value_text', f.value ->> 'text')) order by t.ctid), '[]'::jsonb) into v_rows
    from "better_supabase"."field_values" t
    join jsonb_array_elements(v_fields) f on f.value ->> 'id' = t."id"::text
    where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
    if jsonb_array_length(v_rows) > 0 then
      v_parts := v_parts || jsonb_build_object('better_supabase.field_values', v_rows);
    end if;
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*) - array['token_hash', 'password_hash']::text[]) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."share_links" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.share_links', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."recurrence_rules" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.recurrence_rules', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reminders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reminders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."import_records" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.import_records', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_members" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_members', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."calendar_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.calendar_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."versions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.versions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."trash_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.trash_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reactions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reactions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reaction_scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reaction_scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."approval_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.approval_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."access_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.access_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."form_submissions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.form_submissions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."signature_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.signature_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."template_applications" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.template_applications', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."pipeline_stage_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.pipeline_stage_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."engagement_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.engagement_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."sla_clocks" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.sla_clocks', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."moderation_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.moderation_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."automation_evaluations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.automation_evaluations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."passes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.passes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_rates" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_rates', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."work_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.work_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."shipments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.shipments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."conversations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.conversations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."message_record_mentions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.message_record_mentions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."channels" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.channels', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."timeline_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.timeline_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."mail_thread_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.mail_thread_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."field_changes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.field_changes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgements" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgements', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_notices" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_notices', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."consents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."observations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.observations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."medication_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.medication_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."care_plans" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.care_plans', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."funding_awards" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.funding_awards', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."care_alerts" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.care_alerts', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."prescriptions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.prescriptions', v_rows);
  end if;
  insert into "better_supabase"."data_exports" ("subject", "organization_id", "subject_type", "subject_id", "format")
  values ('record', v_tenant, request_subject_export.subject_type, request_subject_export.subject_id, request_subject_export.format)
  returning * into v_row;
  insert into "better_supabase"."data_export_contents" ("export_id", "parts") values (v_row."id", v_parts);
  perform "better_supabase".emit_event('data_export.requested', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'data-exports/' || v_row."id"::text, (v_row."organization_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.requested',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."organization_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sign_prescription (
  prescription_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."prescriptions";
  v_order "better_supabase"."medication_orders";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."prescriptions" x where x."id" = sign_prescription.prescription_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.read'), false))) then
    raise exception 'no such prescription' using errcode = 'P0002', hint = 'PRESCRIPTION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'e_prescribing.sign'), false))) then
    raise exception 'not allowed to sign prescriptions' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."prescriber_id" is distinct from auth.uid() or auth.uid() is null then
    raise exception 'only the prescriber signs a prescription' using errcode = '42501', hint = 'PRESCRIPTION_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft can be signed' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."tenant_id" = v_row."tenant_id" and x."id" = v_row."order_id";
  if not found or v_order."status" <> 'active' or (v_order."ends_on" is not null and v_order."ends_on" < (now() at time zone 'UTC')::date) then
    raise exception 'the order is no longer active' using errcode = '55000', hint = 'PRESCRIPTION_STATUS';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_prescription_sign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."prescriptions" x set "status" = 'signed', "signed_by" = auth.uid(), "signed_at" = now(),
    "snapshot" = "better_supabase"."prescription_order_snapshot"(v_row."tenant_id", v_row."order_id"), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('prescription.signed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'prescriptions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/e-prescribing');
  perform better_supabase.audit_event(
    event_type => 'prescription.signed',
    category => 'data',
    target_type => 'prescription',
    record_id => v_row."id"::text,
    target_label => v_row."status",
    summary => 'prescription signed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_prescription_sign"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'prescriberId', v_row."prescriber_id", 'prescriberName', v_row."prescriber_name", 'status', v_row."status", 'order', v_row."snapshot", 'signedBy', v_row."signed_by", 'signedAt', v_row."signed_at", 'gateway', v_row."gateway", 'gatewayReference', v_row."gateway_reference", 'sentAt', v_row."sent_at", 'deliveryError', v_row."delivery_error", 'dispensedAt', v_row."dispensed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."prescriptions"
  ADD CONSTRAINT "prescriptions_tenant_id_order_id_fkey" FOREIGN KEY (tenant_id, order_id) REFERENCES better_supabase.medication_orders(tenant_id, id);

CREATE UNIQUE INDEX prescriptions_live_order_key ON better_supabase.prescriptions USING btree (tenant_id, order_id)
  WHERE (status <> 'cancelled'::text);

CREATE INDEX prescriptions_status_idx ON better_supabase.prescriptions USING btree (tenant_id, status);

CREATE INDEX prescriptions_subject_idx ON better_supabase.prescriptions USING btree (tenant_id, subject_type, subject_id);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."prescriptions"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."prescriptions"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."prescriptions"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('e_prescribing.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."prescriptions"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "prescriptions_read" ON "better_supabase"."prescriptions"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('e_prescribing.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."cancel_prescription"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."cancel_prescription"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_prescription"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_prescription"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_prescription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_prescription"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_prescriptions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_prescriptions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_prescription_delivery"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_prescription_delivery"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_prescription_dispense"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_prescription_dispense"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."sign_prescription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sign_prescription"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."cancel_prescription"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."cancel_prescription"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_prescription"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_prescription"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_prescription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_prescription"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_prescriptions"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_prescriptions"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."prescription_order_snapshot"(uuid, uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."record_prescription_delivery"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_prescription_delivery"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_prescription_dispense"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_prescription_dispense"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sign_prescription"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sign_prescription"(uuid) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."prescriptions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."prescriptions" TO "service_role";
