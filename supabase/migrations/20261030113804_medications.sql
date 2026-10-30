SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."medication_administrations" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "order_id"        uuid                     NOT NULL,
  "scheduled_at"    timestamp with time zone,
  "administered_at" timestamp with time zone,
  "status"          text                     NOT NULL DEFAULT 'planned'::text,
  "dose"            numeric,
  "performer_id"    uuid,
  "checked_by"      uuid,
  "reason"          text,
  "note"            text,
  CONSTRAINT "medication_administrations_check" CHECK (((checked_by IS NULL) OR (checked_by IS DISTINCT FROM performer_id))),
  CONSTRAINT "medication_administrations_dose_check" CHECK (((dose IS NULL) OR (dose > (0)::numeric))),
  CONSTRAINT "medication_administrations_note_check" CHECK (((note IS NULL) OR (length(note) <= 2000))),
  CONSTRAINT "medication_administrations_order_id_scheduled_at_key" UNIQUE (order_id, scheduled_at),
  CONSTRAINT "medication_administrations_pkey" PRIMARY KEY (id),
  CONSTRAINT "medication_administrations_reason_check" CHECK (((reason IS NULL) OR (length(reason) <= 1000))),
  CONSTRAINT "medication_administrations_status_check" CHECK ((status = ANY (ARRAY['planned'::text, 'given'::text, 'refused'::text, 'skipped'::text, 'missed'::text])))
);

ALTER TABLE "better_supabase"."medication_administrations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."medication_orders" (
  "id"                    uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"             uuid                     NOT NULL,
  "subject_type"          text                     NOT NULL,
  "subject_id"            text                     NOT NULL,
  "medication_id"         uuid                     NOT NULL,
  "dose"                  numeric                  NOT NULL,
  "dose_unit"             text                     NOT NULL,
  "route"                 text,
  "schedule"              jsonb,
  "as_needed"             boolean                  NOT NULL DEFAULT false,
  "as_needed_reason"      text,
  "max_per_day"           numeric,
  "starts_on"             date                     NOT NULL,
  "ends_on"               date,
  "prescriber"            text,
  "source"                text                     NOT NULL DEFAULT 'prescriber'::text,
  "external_id"           text,
  "requires_double_check" boolean                  NOT NULL DEFAULT false,
  "status"                text                     NOT NULL DEFAULT 'active'::text,
  "stopped_reason"        text,
  "created_by"            uuid,
  "created_at"            timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"            timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "medication_orders_as_needed_reason_check" CHECK (((as_needed_reason IS NULL) OR (length(as_needed_reason) <= 500))),
  CONSTRAINT "medication_orders_check1" CHECK ((as_needed OR (schedule IS NOT NULL))),
  CONSTRAINT "medication_orders_check" CHECK (((ends_on IS NULL) OR (ends_on >= starts_on))),
  CONSTRAINT "medication_orders_dose_check" CHECK ((dose > (0)::numeric)),
  CONSTRAINT "medication_orders_dose_unit_check" CHECK (((length(dose_unit) >= 1) AND (length(dose_unit) <= 50))),
  CONSTRAINT "medication_orders_external_id_check" CHECK (((external_id IS NULL) OR (length(external_id) <= 200))),
  CONSTRAINT "medication_orders_max_per_day_check" CHECK (((max_per_day IS NULL) OR (max_per_day > (0)::numeric))),
  CONSTRAINT "medication_orders_pkey" PRIMARY KEY (id),
  CONSTRAINT "medication_orders_prescriber_check" CHECK (((prescriber IS NULL) OR (length(prescriber) <= 300))),
  CONSTRAINT "medication_orders_route_check" CHECK (((route IS NULL) OR (length(route) <= 100))),
  CONSTRAINT "medication_orders_source_check" CHECK ((source = ANY (ARRAY['prescriber'::text, 'pharmacy'::text, 'import'::text]))),
  CONSTRAINT "medication_orders_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'stopped'::text]))),
  CONSTRAINT "medication_orders_stopped_reason_check" CHECK (((stopped_reason IS NULL) OR (length(stopped_reason) <= 1000))),
  CONSTRAINT "medication_orders_tenant_id_id_key" UNIQUE (tenant_id, id)
);

ALTER TABLE "better_supabase"."medication_orders"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."medications" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "name"        text                     NOT NULL,
  "code_system" text                     NOT NULL DEFAULT 'custom'::text,
  "code"        text,
  "form"        text,
  "strength"    text,
  "unit"        text                     NOT NULL,
  "high_risk"   boolean                  NOT NULL DEFAULT false,
  "archived_at" timestamp with time zone,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "medications_code_check" CHECK (((code IS NULL) OR ((length(code) >= 1) AND (length(code) <= 100)))),
  CONSTRAINT "medications_code_system_check" CHECK ((code_system = ANY (ARRAY['gtin'::text, 'hpk'::text, 'atc'::text, 'rxnorm'::text, 'custom'::text]))),
  CONSTRAINT "medications_form_check" CHECK (((form IS NULL) OR (length(form) <= 100))),
  CONSTRAINT "medications_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 300))),
  CONSTRAINT "medications_pkey" PRIMARY KEY (id),
  CONSTRAINT "medications_strength_check" CHECK (((strength IS NULL) OR (length(strength) <= 100))),
  CONSTRAINT "medications_tenant_id_id_key" UNIQUE (tenant_id, id),
  CONSTRAINT "medications_unit_check" CHECK (((length(unit) >= 1) AND (length(unit) <= 50)))
);

ALTER TABLE "better_supabase"."medications"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.archive_medication (
  medication_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_medication"($1) $function$;

CREATE OR REPLACE FUNCTION api.import_medication (
  tenant uuid,
  item   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_medication"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.import_medication_orders (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_medication_orders"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_medications (
  tenant           uuid,
  search           text    DEFAULT NULL::text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_medications"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.mark_missed_medication_administrations()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_missed_medication_administrations"() $function$;

CREATE OR REPLACE FUNCTION api.medication_chart (
  subject_type text,
  subject_id   text,
  since        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."medication_chart"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.medication_orders_of (
  subject_type    text,
  subject_id      text,
  include_stopped boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."medication_orders_of"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.pause_medication_order (
  order_id uuid,
  paused   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pause_medication_order"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.plan_medication_administrations (
  tenant uuid,
  until  timestamp with time zone
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."plan_medication_administrations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.prescribe_medication (
  tenant        uuid,
  subject_type  text,
  subject_id    text,
  medication_id uuid,
  attrs         jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."prescribe_medication"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.record_as_needed_administration (
  order_id   uuid,
  dose       numeric DEFAULT NULL::numeric,
  reason     text    DEFAULT NULL::text,
  checked_by uuid    DEFAULT NULL::uuid,
  note       text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_as_needed_administration"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.record_medication_administration (
  administration_id uuid,
  status            text,
  dose              numeric DEFAULT NULL::numeric,
  reason            text    DEFAULT NULL::text,
  checked_by        uuid    DEFAULT NULL::uuid,
  note              text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_medication_administration"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.save_medication (
  tenant        uuid,
  name          text,
  unit          text,
  code_system   text    DEFAULT 'custom'::text,
  code          text    DEFAULT NULL::text,
  form          text    DEFAULT NULL::text,
  strength      text    DEFAULT NULL::text,
  high_risk     boolean DEFAULT false,
  medication_id uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_medication"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.stop_medication_order (
  order_id uuid,
  reason   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stop_medication_order"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.update_medication_order (
  order_id uuid,
  attrs    jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_medication_order"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_medication (
  medication_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_medication "better_supabase"."medications"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_medication from "better_supabase"."medications" x where x."id" = archive_medication.medication_id;
  if not found then
    raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_medication."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to change the medication catalog' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  update "better_supabase"."medications" x set "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = v_medication."id"
  returning x.* into v_medication;
  return jsonb_build_object('id', v_medication."id", 'organizationId', v_medication."tenant_id", 'name', v_medication."name", 'codeSystem', v_medication."code_system", 'code', v_medication."code", 'form', v_medication."form", 'strength', v_medication."strength", 'unit', v_medication."unit", 'highRisk', v_medication."high_risk", 'archivedAt', v_medication."archived_at", 'createdAt', v_medication."created_at", 'updatedAt', v_medication."updated_at");
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
    ('user', 'better_supabase.contacts', '"better_supabase"."contacts"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_document_versions', '"better_supabase"."ai_document_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_suggestions', '"better_supabase"."ai_suggestions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.memories', '"better_supabase"."memories"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.expense_reports', '"better_supabase"."expense_reports"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pledges', '"better_supabase"."pledges"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.donations', '"better_supabase"."donations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_orders', '"better_supabase"."work_orders"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dispatch_routes', '"better_supabase"."dispatch_routes"', 'technician_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_order_parts', '"better_supabase"."work_order_parts"', 'recorded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.shipments', '"better_supabase"."shipments"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.contracts', '"better_supabase"."contracts"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'collected_by', true, '{}'::text[], true),
    ('user', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'enrolled_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.contacts', '"better_supabase"."contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contact_identities', '"better_supabase"."contact_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_conversations', '"better_supabase"."inbox_conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_message_details', '"better_supabase"."inbox_message_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbound_events', '"better_supabase"."inbound_events"', 'tenant_id', true, array['headers']::text[], true),
    ('organization', 'better_supabase.message_templates', '"better_supabase"."message_templates"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_message_embeddings', '"better_supabase"."ai_message_embeddings"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.price_lists', '"better_supabase"."price_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_prices', '"better_supabase"."product_prices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.categories', '"better_supabase"."categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_categories', '"better_supabase"."product_categories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_collections', '"better_supabase"."product_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channels', '"better_supabase"."catalog_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.catalog_channel_products', '"better_supabase"."catalog_channel_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_translations', '"better_supabase"."product_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_variant_translations', '"better_supabase"."product_variant_translations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.product_media', '"better_supabase"."product_media"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.stock_items', '"better_supabase"."stock_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_bins', '"better_supabase"."stock_bins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_lots', '"better_supabase"."stock_lots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_serials', '"better_supabase"."stock_serials"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_buckets', '"better_supabase"."stock_buckets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_allocations', '"better_supabase"."stock_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.carts', '"better_supabase"."carts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.cart_lines', '"better_supabase"."cart_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.shipping_rates', '"better_supabase"."shipping_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.orders', '"better_supabase"."orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_lines', '"better_supabase"."order_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.order_payments', '"better_supabase"."order_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillments', '"better_supabase"."fulfillments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.fulfillment_lines', '"better_supabase"."fulfillment_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.person_inbox_contacts', '"better_supabase"."person_inbox_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagements', '"better_supabase"."engagements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.engagement_subjects', '"better_supabase"."engagement_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.passes', '"better_supabase"."passes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pass_check_ins', '"better_supabase"."pass_check_ins"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_rates', '"better_supabase"."time_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.time_invoice_entries', '"better_supabase"."time_invoice_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lease_agreements', '"better_supabase"."lease_agreements"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.contracts', '"better_supabase"."contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.contract_obligations', '"better_supabase"."contract_obligations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_frameworks', '"better_supabase"."control_frameworks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.controls', '"better_supabase"."controls"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.control_evidence', '"better_supabase"."control_evidence"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.evidence_tasks', '"better_supabase"."evidence_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policies', '"better_supabase"."policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.policy_acknowledgements', '"better_supabase"."policy_acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_components', '"better_supabase"."status_components"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_component_history', '"better_supabase"."status_component_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incidents', '"better_supabase"."incidents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_updates', '"better_supabase"."incident_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_impacts', '"better_supabase"."incident_impacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_postmortems', '"better_supabase"."incident_postmortems"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_pages', '"better_supabase"."status_pages"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.sequence_enrollments', '"better_supabase"."sequence_enrollments"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.accounting_tax_codes', '"better_supabase"."accounting_tax_codes"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.medication_administrations', '"better_supabase"."medication_administrations"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_medication (
  tenant uuid,
  item   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_medication "better_supabase"."medications"%rowtype;
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', import_medication.tenant, 'medications.prescribe'), false)) then
    raise exception 'not allowed to change the medication catalog' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if import_medication.item is null or jsonb_typeof(import_medication.item) <> 'object' then
    raise exception 'a catalog item is an object' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  v_name := nullif(trim(import_medication.item ->> 'name'), '');
  v_med_unit := nullif(trim(import_medication.item ->> 'unit'), '');
  v_system := coalesce(nullif(trim(import_medication.item ->> 'codeSystem'), ''), 'custom');
  v_code := nullif(trim(import_medication.item ->> 'code'), '');
  v_form := nullif(trim(import_medication.item ->> 'form'), '');
  v_strength := nullif(trim(import_medication.item ->> 'strength'), '');
  v_high_risk := coalesce((import_medication.item ->> 'highRisk')::boolean, false);
  if v_name is null or length(v_name) > 300 then
    raise exception 'a medication needs a name of at most 300 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    raise exception 'a medication needs a unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system is null or v_system not in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom') then
    raise exception 'code_system is gtin, hpk, atc, rxnorm or custom' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_code is not null and length(v_code) > 100 then
    raise exception 'a code is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system <> 'custom' and v_code is null then
    raise exception 'a medication from a catalog needs its code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    raise exception 'form and strength are at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."tenant_id" = import_medication.tenant and x."code_system" = v_system and x."code" = v_code
  for update;
  if found then
    update "better_supabase"."medications" x set
    "name" = v_name,
    "code_system" = v_system,
    "code" = v_code,
    "form" = v_form,
    "strength" = v_strength,
    "unit" = v_med_unit,
    "high_risk" = v_high_risk,
    "updated_at" = now()
    where x."id" = v_medication."id"
    returning x.* into v_medication;
  else
    insert into "better_supabase"."medications" ("tenant_id", "name", "code_system", "code", "form", "strength", "unit", "high_risk")
    values (import_medication.tenant, v_name, v_system, v_code, v_form, v_strength, v_med_unit, v_high_risk)
    returning * into v_medication;
  end if;
  return jsonb_build_object('id', v_medication."id", 'organizationId', v_medication."tenant_id", 'name', v_medication."name", 'codeSystem', v_medication."code_system", 'code', v_medication."code", 'form', v_medication."form", 'strength', v_medication."strength", 'unit', v_medication."unit", 'highRisk', v_medication."high_risk", 'archivedAt', v_medication."archived_at", 'createdAt', v_medication."created_at", 'updatedAt', v_medication."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_medication_orders (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_medication "better_supabase"."medications"%rowtype;
  v_item jsonb;
  v_external text;
  v_created jsonb := '[]'::jsonb;
  v_skipped integer := 0;
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if import_medication_orders.items is null or jsonb_typeof(import_medication_orders.items) <> 'array' then
    raise exception 'items is an array' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(import_medication_orders.items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'each item is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    v_external := nullif(trim(v_item ->> 'externalId'), '');
    if v_external is null then
      raise exception 'each imported order needs an externalId' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."medication_orders" x where x."tenant_id" = import_medication_orders.tenant and x."external_id" = v_external) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    if not (case (v_item ->> 'subjectType')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'subjectType'), (v_item ->> 'subjectId'), 'read')) then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if jsonb_typeof(v_item -> 'medication') = 'object' then
      v_name := nullif(trim((v_item -> 'medication') ->> 'name'), '');
  v_med_unit := nullif(trim((v_item -> 'medication') ->> 'unit'), '');
  v_system := coalesce(nullif(trim((v_item -> 'medication') ->> 'codeSystem'), ''), 'custom');
  v_code := nullif(trim((v_item -> 'medication') ->> 'code'), '');
  v_form := nullif(trim((v_item -> 'medication') ->> 'form'), '');
  v_strength := nullif(trim((v_item -> 'medication') ->> 'strength'), '');
  v_high_risk := coalesce(((v_item -> 'medication') ->> 'highRisk')::boolean, false);
  if v_name is null or length(v_name) > 300 then
    raise exception 'a medication needs a name of at most 300 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    raise exception 'a medication needs a unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system is null or v_system not in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom') then
    raise exception 'code_system is gtin, hpk, atc, rxnorm or custom' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_code is not null and length(v_code) > 100 then
    raise exception 'a code is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system <> 'custom' and v_code is null then
    raise exception 'a medication from a catalog needs its code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    raise exception 'form and strength are at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."tenant_id" = import_medication_orders.tenant and x."code_system" = v_system and x."code" = v_code
  for update;
  if found then
    update "better_supabase"."medications" x set
    "name" = v_name,
    "code_system" = v_system,
    "code" = v_code,
    "form" = v_form,
    "strength" = v_strength,
    "unit" = v_med_unit,
    "high_risk" = v_high_risk,
    "updated_at" = now()
    where x."id" = v_medication."id"
    returning x.* into v_medication;
  else
    insert into "better_supabase"."medications" ("tenant_id", "name", "code_system", "code", "form", "strength", "unit", "high_risk")
    values (import_medication_orders.tenant, v_name, v_system, v_code, v_form, v_strength, v_med_unit, v_high_risk)
    returning * into v_medication;
  end if;
    else
      select * into v_medication from "better_supabase"."medications" x
      where x."id" = (v_item ->> 'medicationId')::uuid and x."tenant_id" = import_medication_orders.tenant;
      if not found then
        raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
      end if;
    end if;
    v_dose := case when v_item ? 'dose' then ((v_item -> 'dose') #>> '{}')::numeric else null end;
  v_unit := case when v_item ? 'doseUnit' then nullif(trim((v_item -> 'doseUnit') #>> '{}'), '') else v_medication."unit" end;
  v_route := case when v_item ? 'route' then nullif(trim((v_item -> 'route') #>> '{}'), '') else null end;
  v_schedule := case when v_item ? 'schedule' then nullif((v_item -> 'schedule'), 'null'::jsonb) else null end;
  v_as_needed := coalesce(case when v_item ? 'asNeeded' then ((v_item -> 'asNeeded') #>> '{}')::boolean else null end, false);
  v_as_needed_reason := case when v_item ? 'asNeededReason' then nullif(trim((v_item -> 'asNeededReason') #>> '{}'), '') else null end;
  v_max := case when v_item ? 'maxPerDay' then ((v_item -> 'maxPerDay') #>> '{}')::numeric else null end;
  v_starts := case when v_item ? 'startsOn' then ((v_item -> 'startsOn') #>> '{}')::date else (now() at time zone 'UTC')::date end;
  v_ends := case when v_item ? 'endsOn' then ((v_item -> 'endsOn') #>> '{}')::date else null end;
  v_prescriber := case when v_item ? 'prescriber' then nullif(trim((v_item -> 'prescriber') #>> '{}'), '') else null end;
  v_double := coalesce(case when v_item ? 'requiresDoubleCheck' then ((v_item -> 'requiresDoubleCheck') #>> '{}')::boolean else null end, false);
    if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
    
    insert into "better_supabase"."medication_orders" ("tenant_id", "subject_type", "subject_id", "medication_id", "dose", "dose_unit", "route", "schedule", "as_needed", "as_needed_reason", "max_per_day", "starts_on", "ends_on", "prescriber", "source", "external_id", "requires_double_check", "created_by")
    values (import_medication_orders.tenant, v_item ->> 'subjectType', v_item ->> 'subjectId', v_medication."id", v_dose, v_unit, v_route, v_schedule, v_as_needed, v_as_needed_reason, v_max, v_starts, v_ends, v_prescriber, coalesce(nullif(v_item ->> 'source', ''), 'import'), v_external, v_double, (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('medication_order.created', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.created',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication prescribed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return jsonb_build_object('created', v_created, 'skipped', v_skipped);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_medications (
  tenant           uuid,
  search           text    DEFAULT NULL::text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'codeSystem', x."code_system", 'code', x."code", 'form', x."form", 'strength', x."strength", 'unit', x."unit", 'highRisk', x."high_risk", 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name", x."id"), '[]'::jsonb)
  from "better_supabase"."medications" x
  where x."tenant_id" = list_medications.tenant
    and (coalesce(list_medications.include_archived, false) or x."archived_at" is null)
    and (nullif(trim(list_medications.search), '') is null
      or x."name" ilike '%' || trim(list_medications.search) || '%'
      or x."code" = trim(list_medications.search))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_missed_medication_administrations()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_count integer := 0;
  v_claims text;
begin
  for v_row in
    update "better_supabase"."medication_administrations" x set "status" = 'missed'
    where x."status" = 'planned' and x."scheduled_at" < now() - interval '60 minutes'
    returning x.*
  loop
    select * into v_order from "better_supabase"."medication_orders" x where x."id" = v_row."order_id";
    perform "better_supabase".emit_event('medication_administration.missed', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at"), 'medication-orders/' || v_row."order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_administration.missed',
    category => 'data',
    target_type => 'medication_administration',
    record_id => v_row."id"::text,
    summary => 'Medication dose missed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at")
  );
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'medication_administration.missed',
      'tenant', v_row."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', v_order."subject_type",
      'subject_id', v_order."subject_id"::text,
      'summary', 'A medication dose was missed',
      'permission', 'medications.manage',
      'watchers', false,
      'key', 'medication_administration.missed:' || v_row."id"::text,
      'data', jsonb_build_object('medicationOrderId', v_order."id", 'scheduledAt', v_row."scheduled_at")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.medication_chart (
  subject_type text,
  subject_id   text,
  since        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with bounds as (
    select
      coalesce(medication_chart.since, (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) as since,
      coalesce(medication_chart.until, ((date_trunc('day', now() at time zone 'UTC') + interval '1 day') at time zone 'UTC')) as until
  )
  select jsonb_build_object(
    'since', b.since,
    'until', b.until,
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'medicationId', x."medication_id", 'dose', x."dose", 'doseUnit', x."dose_unit", 'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed", 'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'prescriber', x."prescriber", 'source', x."source", 'externalId', x."external_id", 'requiresDoubleCheck', x."requires_double_check", 'status', x."status", 'stoppedReason', x."stopped_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('medication', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'codeSystem', y."code_system", 'code', y."code", 'form', y."form", 'strength', y."strength", 'unit', y."unit", 'highRisk', y."high_risk", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on", x."id")
      from "better_supabase"."medication_orders" x
      join "better_supabase"."medications" y on y."tenant_id" = x."tenant_id" and y."id" = x."medication_id"
      where x."subject_type" = medication_chart.subject_type
        and x."subject_id" = medication_chart.subject_id
        and x."starts_on" <= (b.until at time zone 'UTC')::date
        and (x."ends_on" is null or x."ends_on" >= (b.since at time zone 'UTC')::date)
    ), '[]'::jsonb),
    'administrations', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'orderId', z."order_id", 'scheduledAt', z."scheduled_at", 'administeredAt', z."administered_at", 'status', z."status", 'dose', z."dose", 'performerId', z."performer_id", 'checkedBy', z."checked_by", 'reason', z."reason", 'note', z."note") order by coalesce(z."scheduled_at", z."administered_at"), z."id")
      from "better_supabase"."medication_administrations" z
      join "better_supabase"."medication_orders" x on x."tenant_id" = z."tenant_id" and x."id" = z."order_id"
      where x."subject_type" = medication_chart.subject_type
        and x."subject_id" = medication_chart.subject_id
        and coalesce(z."scheduled_at", z."administered_at") >= b.since
        and coalesce(z."scheduled_at", z."administered_at") < b.until
    ), '[]'::jsonb)
  )
  from bounds b
$function$;

CREATE OR REPLACE FUNCTION better_supabase.medication_orders_of (
  subject_type    text,
  subject_id      text,
  include_stopped boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'medicationId', x."medication_id", 'dose', x."dose", 'doseUnit', x."dose_unit", 'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed", 'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'prescriber', x."prescriber", 'source', x."source", 'externalId', x."external_id", 'requiresDoubleCheck', x."requires_double_check", 'status', x."status", 'stoppedReason', x."stopped_reason", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('medication', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'codeSystem', y."code_system", 'code', y."code", 'form', y."form", 'strength', y."strength", 'unit', y."unit", 'highRisk', y."high_risk", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."medication_orders" x
  join "better_supabase"."medications" y on y."tenant_id" = x."tenant_id" and y."id" = x."medication_id"
  where x."subject_type" = medication_orders_of.subject_type
    and x."subject_id" = medication_orders_of.subject_id
    and (coalesce(medication_orders_of.include_stopped, false) or x."status" <> 'stopped')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.medications_subject_merge (
  subject_table text,
  keep          text,
  drop          text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.qualification_types' then array['qualification_type'] when 'better_supabase.risks' then array['risk'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.forms' then array['form'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.change_requests' then array['change_request'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    update "better_supabase"."medication_orders" x set "subject_id" = v_keep where x."subject_type" = v_type and x."subject_id" = v_drop;
  end loop;
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
    when 'catalog.manage' then 'catalog.manage'
    when 'catalog.read' then 'catalog.read'
    when 'channels.create' then 'channels.create'
    when 'channels.manage' then 'channels.manage'
    when 'channels.read' then 'messages.read'
    when 'comments.create' then 'messages.send'
    when 'comments.moderate' then 'messages.moderate'
    when 'comments.read' then 'messages.read'
    when 'compliance.acknowledge' then 'compliance.acknowledge'
    when 'compliance.collect' then 'compliance.collect'
    when 'compliance.manage' then 'compliance.manage'
    when 'compliance.read' then 'compliance.read'
    when 'connectors.manage' then 'connectors.manage'
    when 'connectors.read' then 'connectors.read'
    when 'connectors.use' then 'connectors.use'
    when 'consents.manage' then 'consents.manage'
    when 'consents.read' then 'consents.read'
    when 'consents.record' then 'consents.record'
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
    when 'data-lifecycle.cancelDelete' then 'organization.delete'
    when 'data-lifecycle.delete' then 'organization.delete'
    when 'data-lifecycle.export' then 'data_lifecycle.export'
    when 'deals.manage' then 'deals.manage'
    when 'deals.read' then 'deals.read'
    when 'deals.write' then 'deals.write'
    when 'dispatch.manage' then 'dispatch.manage'
    when 'dispatch.read' then 'dispatch.read'
    when 'dispatch.work' then 'dispatch.work'
    when 'documents.manage' then 'documents.manage'
    when 'documents.read' then 'documents.read'
    when 'documents.suggest' then 'documents.suggest'
    when 'documents.write' then 'documents.write'
    when 'donations.manage' then 'donations.manage'
    when 'donations.read' then 'donations.read'
    when 'drive.create' then 'drive.create'
    when 'drive.manage' then 'drive.manage'
    when 'drive.read' then 'drive.read'
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
    when 'inventory.manage' then 'inventory.manage'
    when 'inventory.purchase' then 'inventory.purchase'
    when 'inventory.read' then 'inventory.read'
    when 'inventory.reserve' then 'inventory.reserve'
    when 'invitations.invite' then 'members.invite'
    when 'invitations.invitePlatform' then 'platform.invite'
    when 'invitations.revoke' then 'members.invite'
    when 'invitations.view' then 'members.invite'
    when 'invoices.manage' then 'invoices.manage'
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
    when 'mail-sync.connect' then 'mail_sync.connect'
    when 'mail-sync.manage' then 'mail_sync.manage'
    when 'mail-sync.read' then 'mail_sync.read'
    when 'mail-sync.send' then 'mail_sync.send'
    when 'medications.administer' then 'medications.administer'
    when 'medications.manage' then 'medications.manage'
    when 'medications.prescribe' then 'medications.prescribe'
    when 'medications.read' then 'medications.read'
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
    when 'teams.manage' then 'teams.manage'
    when 'teams.read' then 'teams.read'
    when 'templates.apply' then 'templates.apply'
    when 'templates.manage' then 'templates.manage'
    when 'templates.read' then 'templates.read'
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

CREATE OR REPLACE FUNCTION better_supabase.pause_medication_order (
  order_id uuid,
  paused   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_status text := case when coalesce(pause_medication_order.paused, true) then 'paused' else 'active' end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = pause_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_row."status" = 'stopped' then
    raise exception 'the medication order is stopped' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_row."status" = v_status then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."medication_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  if v_status = 'paused' then
    delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
    perform "better_supabase".emit_event('medication_order.paused', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.paused',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order paused',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('medication_order.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.updated',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order resumed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.plan_medication_administrations (
  tenant uuid,
  until  timestamp with time zone
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_order "better_supabase"."medication_orders"%rowtype;
  v_until timestamptz;
  v_today date := (now() at time zone 'UTC')::date;
  v_last date;
  v_count integer := 0;
  v_planned integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', plan_medication_administrations.tenant, 'medications.manage'), false)) then
    raise exception 'not allowed to plan medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if plan_medication_administrations.until is null then
    raise exception 'planning needs an end time' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_until := least(plan_medication_administrations.until, now() + interval '31 days');
  v_last := (v_until at time zone 'UTC')::date;
  for v_order in
    select * from "better_supabase"."medication_orders" x
    where x."tenant_id" = plan_medication_administrations.tenant
      and x."status" = 'active'
      and x."schedule" is not null
      and x."starts_on" <= v_last
      and (x."ends_on" is null or x."ends_on" >= v_today)
  loop
    insert into "better_supabase"."medication_administrations" ("tenant_id", "order_id", "scheduled_at", "status", "dose")
    select v_order."tenant_id", v_order."id", s.at, 'planned', v_order."dose"
    from (
      select ((d.day + make_interval(mins => t.minute)) at time zone 'UTC') as at
      from generate_series(0, least(coalesce(v_order."ends_on", v_last), v_last) - greatest(v_order."starts_on", v_today)) as g(n)
      cross join lateral (select greatest(v_order."starts_on", v_today) + g.n as day) d
      cross join lateral (
        select split_part(x #>> '{}', ':', 1)::integer * 60 + split_part(x #>> '{}', ':', 2)::integer as minute
        from jsonb_array_elements(coalesce(v_order."schedule" -> 'times', '[]'::jsonb)) x
        union
        select coalesce(split_part(v_order."schedule" ->> 'startTime', ':', 1)::integer * 60 + split_part(v_order."schedule" ->> 'startTime', ':', 2)::integer, 0) + k * (v_order."schedule" ->> 'everyHours')::integer * 60
        from generate_series(0, 23) k
        where v_order."schedule" ? 'everyHours' and coalesce(split_part(v_order."schedule" ->> 'startTime', ':', 1)::integer * 60 + split_part(v_order."schedule" ->> 'startTime', ':', 2)::integer, 0) + k * (v_order."schedule" ->> 'everyHours')::integer * 60 < 1440
      ) t
      where not (v_order."schedule" ? 'weekdays')
        or extract(isodow from d.day)::integer in (select (w #>> '{}')::integer from jsonb_array_elements(v_order."schedule" -> 'weekdays') w)
    ) s
    where s.at > now() and s.at <= v_until
    on conflict ("order_id", "scheduled_at") do nothing;
    get diagnostics v_planned = row_count;
    v_count := v_count + v_planned;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prescribe_medication (
  tenant        uuid,
  subject_type  text,
  subject_id    text,
  medication_id uuid,
  attrs         jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_medication "better_supabase"."medications"%rowtype;
  v_attrs jsonb := coalesce(prescribe_medication.attrs, '{}'::jsonb);
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', prescribe_medication.tenant, 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if not (case prescribe_medication.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      else false
    end and "better_supabase"."can_subject"(prescribe_medication.subject_type, prescribe_medication.subject_id, 'read')) then
    raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."id" = prescribe_medication.medication_id and x."tenant_id" = prescribe_medication.tenant and x."archived_at" is null;
  if not found then
    raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_dose := case when v_attrs ? 'dose' then ((v_attrs -> 'dose') #>> '{}')::numeric else null end;
  v_unit := case when v_attrs ? 'doseUnit' then nullif(trim((v_attrs -> 'doseUnit') #>> '{}'), '') else v_medication."unit" end;
  v_route := case when v_attrs ? 'route' then nullif(trim((v_attrs -> 'route') #>> '{}'), '') else null end;
  v_schedule := case when v_attrs ? 'schedule' then nullif((v_attrs -> 'schedule'), 'null'::jsonb) else null end;
  v_as_needed := coalesce(case when v_attrs ? 'asNeeded' then ((v_attrs -> 'asNeeded') #>> '{}')::boolean else null end, false);
  v_as_needed_reason := case when v_attrs ? 'asNeededReason' then nullif(trim((v_attrs -> 'asNeededReason') #>> '{}'), '') else null end;
  v_max := case when v_attrs ? 'maxPerDay' then ((v_attrs -> 'maxPerDay') #>> '{}')::numeric else null end;
  v_starts := case when v_attrs ? 'startsOn' then ((v_attrs -> 'startsOn') #>> '{}')::date else (now() at time zone 'UTC')::date end;
  v_ends := case when v_attrs ? 'endsOn' then ((v_attrs -> 'endsOn') #>> '{}')::date else null end;
  v_prescriber := case when v_attrs ? 'prescriber' then nullif(trim((v_attrs -> 'prescriber') #>> '{}'), '') else null end;
  v_double := coalesce(case when v_attrs ? 'requiresDoubleCheck' then ((v_attrs -> 'requiresDoubleCheck') #>> '{}')::boolean else null end, false);
  if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_order_prescribe"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using prescribe_medication.tenant, prescribe_medication.subject_type, prescribe_medication.subject_id, prescribe_medication.medication_id;
    end if;
  end;
  insert into "better_supabase"."medication_orders" ("tenant_id", "subject_type", "subject_id", "medication_id", "dose", "dose_unit", "route", "schedule", "as_needed", "as_needed_reason", "max_per_day", "starts_on", "ends_on", "prescriber", "source", "external_id", "requires_double_check", "created_by")
    values (prescribe_medication.tenant, prescribe_medication.subject_type, prescribe_medication.subject_id, v_medication."id", v_dose, v_unit, v_route, v_schedule, v_as_needed, v_as_needed_reason, v_max, v_starts, v_ends, v_prescriber, 'prescriber', null, v_double, (select auth.uid()))
    returning * into v_row;
  perform "better_supabase".emit_event('medication_order.created', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.created',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication prescribed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_order_prescribe"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_as_needed_administration (
  order_id   uuid,
  dose       numeric DEFAULT NULL::numeric,
  reason     text    DEFAULT NULL::text,
  checked_by uuid    DEFAULT NULL::uuid,
  note       text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_reason text := nullif(trim(record_as_needed_administration.reason), '');
  v_dose numeric;
  v_given numeric;
  v_today date := (now() at time zone 'UTC')::date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."id" = record_as_needed_administration.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_order."tenant_id", 'medications.administer'), false) and coalesce("better_supabase"."can_subject"(v_order."subject_type", v_order."subject_id", 'read'), false))) then
    raise exception 'not allowed to administer medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if not v_order."as_needed" then
    raise exception 'the order isn''t given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_order."status" <> 'active' or v_order."starts_on" > v_today or v_order."ends_on" < v_today then
    raise exception 'the medication order isn''t active' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_reason is null then
    raise exception 'an as-needed dose needs the reason it was given' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  v_dose := coalesce(record_as_needed_administration.dose, v_order."dose");
  if v_dose <= 0 then
    raise exception 'a dose is above zero' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_order."max_per_day" is not null then
    select coalesce(sum(x."dose"), 0) into v_given from "better_supabase"."medication_administrations" x
    where x."order_id" = v_order."id" and x."status" = 'given' and x."administered_at" > now() - interval '24 hours';
    if v_given + v_dose > v_order."max_per_day" then
      raise exception 'this dose goes over the most the order allows in 24 hours' using errcode = '22023', hint = 'MEDICATION_MAX_DOSE_EXCEEDED';
    end if;
  end if;
  if (coalesce((select y."high_risk" from "better_supabase"."medications" y where y."tenant_id" = v_order."tenant_id" and y."id" = v_order."medication_id"), false) or v_order."requires_double_check") then
    if record_as_needed_administration.checked_by is null then
      raise exception 'this dose needs a second member to check it' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
    if record_as_needed_administration.checked_by = (select auth.uid()) then
      raise exception 'the second check is by another member' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_SELF';
    end if;
    if not coalesce(coalesce(better_supabase.can_user(record_as_needed_administration.checked_by, 'tenant', v_order."tenant_id", 'medications.administer'), false), false) then
      raise exception 'the member who checks may administer medication in this organization' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_administration_record"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_order."id", 'given';
    end if;
  end;
  insert into "better_supabase"."medication_administrations" ("tenant_id", "order_id", "administered_at", "status", "dose", "performer_id", "checked_by", "reason", "note")
  values (v_order."tenant_id", v_order."id", now(), 'given', v_dose, (select auth.uid()), record_as_needed_administration.checked_by, v_reason, nullif(trim(record_as_needed_administration.note), ''))
  returning * into v_row;
  perform "better_supabase".emit_event('medication_administration.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at"), 'medication-orders/' || v_row."order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_administration.recorded',
    category => 'data',
    target_type => 'medication_administration',
    record_id => v_row."id"::text,
    summary => 'Medication dose recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_administration_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at", 'status', v_row."status", 'dose', v_row."dose", 'performerId', v_row."performer_id", 'checkedBy', v_row."checked_by", 'reason', v_row."reason", 'note', v_row."note");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_medication_administration (
  administration_id uuid,
  status            text,
  dose              numeric DEFAULT NULL::numeric,
  reason            text    DEFAULT NULL::text,
  checked_by        uuid    DEFAULT NULL::uuid,
  note              text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_status text := lower(trim(record_medication_administration.status));
  v_reason text := nullif(trim(record_medication_administration.reason), '');
  v_dose numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_administrations" x where x."id" = record_medication_administration.administration_id for update;
  if not found then
    raise exception 'medication dose not found' using errcode = 'P0002', hint = 'MEDICATION_ADMINISTRATION_NOT_FOUND';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."id" = v_row."order_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_order."tenant_id", 'medications.administer'), false) and coalesce("better_supabase"."can_subject"(v_order."subject_type", v_order."subject_id", 'read'), false))) then
    raise exception 'not allowed to administer medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_status is null or v_status not in ('given', 'refused', 'skipped') then
    raise exception 'a dose is recorded as given, refused or skipped' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_row."status" not in ('planned', 'missed') then
    raise exception 'the dose is already recorded' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'the medication order isn''t active' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_status in ('refused', 'skipped') and v_reason is null then
    raise exception 'a refused or skipped dose needs a reason' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_status = 'given' then
    v_dose := coalesce(record_medication_administration.dose, v_row."dose", v_order."dose");
    if v_dose <= 0 then
      raise exception 'a dose is above zero' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
    end if;
    if (coalesce((select y."high_risk" from "better_supabase"."medications" y where y."tenant_id" = v_order."tenant_id" and y."id" = v_order."medication_id"), false) or v_order."requires_double_check") then
    if record_medication_administration.checked_by is null then
      raise exception 'this dose needs a second member to check it' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
    if record_medication_administration.checked_by = (select auth.uid()) then
      raise exception 'the second check is by another member' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_SELF';
    end if;
    if not coalesce(coalesce(better_supabase.can_user(record_medication_administration.checked_by, 'tenant', v_order."tenant_id", 'medications.administer'), false), false) then
      raise exception 'the member who checks may administer medication in this organization' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_administration_record"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_order."id", v_status;
    end if;
  end;
  update "better_supabase"."medication_administrations" x set
    "status" = v_status,
    "administered_at" = now(),
    "dose" = case when v_status = 'given' then v_dose else x."dose" end,
    "performer_id" = (select auth.uid()),
    "checked_by" = case when v_status = 'given' then record_medication_administration.checked_by end,
    "reason" = v_reason, "note" = nullif(trim(record_medication_administration.note), '')
  where x."id" = v_row."id"
  returning x.* into v_row;
  perform "better_supabase".emit_event('medication_administration.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at"), 'medication-orders/' || v_row."order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_administration.recorded',
    category => 'data',
    target_type => 'medication_administration',
    record_id => v_row."id"::text,
    summary => 'Medication dose recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_administration_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at", 'status', v_row."status", 'dose', v_row."dose", 'performerId', v_row."performer_id", 'checkedBy', v_row."checked_by", 'reason', v_row."reason", 'note', v_row."note");
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
    when 'engagement' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."engagements" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.engagements';
      v_reveal := 'engagements_reveal';
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
      from "better_supabase"."lease_agreements" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.lease_agreements';
      v_reveal := 'lease_agreements_reveal';
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
    when 'policy' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."policies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.policies';
      v_reveal := 'policies_reveal';
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
    when 'form' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."forms" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.forms';
      v_reveal := 'forms_reveal';
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
  from "better_supabase"."rule_evaluations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.rule_evaluations', v_rows);
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
  from "better_supabase"."activity_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."organization_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.activity_entries', v_rows);
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
  from "better_supabase"."sequence_enrollments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.sequence_enrollments', v_rows);
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

CREATE OR REPLACE FUNCTION better_supabase.save_medication (
  tenant        uuid,
  name          text,
  unit          text,
  code_system   text    DEFAULT 'custom'::text,
  code          text    DEFAULT NULL::text,
  form          text    DEFAULT NULL::text,
  strength      text    DEFAULT NULL::text,
  high_risk     boolean DEFAULT false,
  medication_id uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_medication "better_supabase"."medications"%rowtype;
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_medication.tenant, 'medications.prescribe'), false)) then
    raise exception 'not allowed to change the medication catalog' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  v_name := nullif(trim(save_medication.name), '');
  v_med_unit := nullif(trim(save_medication.unit), '');
  v_system := coalesce(nullif(trim(save_medication.code_system), ''), 'custom');
  v_code := nullif(trim(save_medication.code), '');
  v_form := nullif(trim(save_medication.form), '');
  v_strength := nullif(trim(save_medication.strength), '');
  v_high_risk := coalesce(save_medication.high_risk, false);
  if v_name is null or length(v_name) > 300 then
    raise exception 'a medication needs a name of at most 300 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    raise exception 'a medication needs a unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system is null or v_system not in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom') then
    raise exception 'code_system is gtin, hpk, atc, rxnorm or custom' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_code is not null and length(v_code) > 100 then
    raise exception 'a code is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system <> 'custom' and v_code is null then
    raise exception 'a medication from a catalog needs its code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    raise exception 'form and strength are at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."medications" x
    where x."tenant_id" = save_medication.tenant and x."code_system" = v_system and x."code" = v_code
      and x."id" is distinct from save_medication.medication_id
  ) then
    raise exception 'the catalog already has a medication with this code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if save_medication.medication_id is null then
    insert into "better_supabase"."medications" ("tenant_id", "name", "code_system", "code", "form", "strength", "unit", "high_risk")
    values (save_medication.tenant, v_name, v_system, v_code, v_form, v_strength, v_med_unit, v_high_risk)
    returning * into v_medication;
  else
    update "better_supabase"."medications" x set
    "name" = v_name,
    "code_system" = v_system,
    "code" = v_code,
    "form" = v_form,
    "strength" = v_strength,
    "unit" = v_med_unit,
    "high_risk" = v_high_risk,
    "archived_at" = null,
    "updated_at" = now()
    where x."id" = save_medication.medication_id and x."tenant_id" = save_medication.tenant
    returning x.* into v_medication;
    if not found then
      raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_medication."id", 'organizationId', v_medication."tenant_id", 'name', v_medication."name", 'codeSystem', v_medication."code_system", 'code', v_medication."code", 'form', v_medication."form", 'strength', v_medication."strength", 'unit', v_medication."unit", 'highRisk', v_medication."high_risk", 'archivedAt', v_medication."archived_at", 'createdAt', v_medication."created_at", 'updatedAt', v_medication."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stop_medication_order (
  order_id uuid,
  reason   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_reason text := nullif(trim(stop_medication_order.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = stop_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_reason is null then
    raise exception 'stopping an order needs a reason' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_row."status" = 'stopped' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_order_stop"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."medication_orders" x set "status" = 'stopped', "stopped_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
  perform "better_supabase".emit_event('medication_order.stopped', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'reason', v_reason), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.stopped',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order stopped',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'reason', v_reason)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_order_stop"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_medication_order (
  order_id uuid,
  attrs    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_attrs jsonb := coalesce(update_medication_order.attrs, '{}'::jsonb);
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = update_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_row."status" = 'stopped' then
    raise exception 'the medication order is stopped' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_dose := case when v_attrs ? 'dose' then ((v_attrs -> 'dose') #>> '{}')::numeric else v_row."dose" end;
  v_unit := case when v_attrs ? 'doseUnit' then nullif(trim((v_attrs -> 'doseUnit') #>> '{}'), '') else v_row."dose_unit" end;
  v_route := case when v_attrs ? 'route' then nullif(trim((v_attrs -> 'route') #>> '{}'), '') else v_row."route" end;
  v_schedule := case when v_attrs ? 'schedule' then nullif((v_attrs -> 'schedule'), 'null'::jsonb) else v_row."schedule" end;
  v_as_needed := coalesce(case when v_attrs ? 'asNeeded' then ((v_attrs -> 'asNeeded') #>> '{}')::boolean else v_row."as_needed" end, false);
  v_as_needed_reason := case when v_attrs ? 'asNeededReason' then nullif(trim((v_attrs -> 'asNeededReason') #>> '{}'), '') else v_row."as_needed_reason" end;
  v_max := case when v_attrs ? 'maxPerDay' then ((v_attrs -> 'maxPerDay') #>> '{}')::numeric else v_row."max_per_day" end;
  v_starts := case when v_attrs ? 'startsOn' then ((v_attrs -> 'startsOn') #>> '{}')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then ((v_attrs -> 'endsOn') #>> '{}')::date else v_row."ends_on" end;
  v_prescriber := case when v_attrs ? 'prescriber' then nullif(trim((v_attrs -> 'prescriber') #>> '{}'), '') else v_row."prescriber" end;
  v_double := coalesce(case when v_attrs ? 'requiresDoubleCheck' then ((v_attrs -> 'requiresDoubleCheck') #>> '{}')::boolean else v_row."requires_double_check" end, false);
  if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  
  update "better_supabase"."medication_orders" x set
    "dose" = v_dose,
    "dose_unit" = v_unit,
    "route" = v_route,
    "schedule" = v_schedule,
    "as_needed" = v_as_needed,
    "as_needed_reason" = v_as_needed_reason,
    "max_per_day" = v_max,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "prescriber" = v_prescriber,
    "requires_double_check" = v_double,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
  perform "better_supabase".emit_event('medication_order.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.updated',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

ALTER TABLE "better_supabase"."medication_administrations"
  ADD CONSTRAINT "medication_administrations_tenant_id_order_id_fkey" FOREIGN KEY (tenant_id, order_id) REFERENCES better_supabase.medication_orders(tenant_id, id)
    ON DELETE CASCADE;

ALTER TABLE "better_supabase"."medication_orders"
  ADD CONSTRAINT "medication_orders_tenant_id_medication_id_fkey" FOREIGN KEY (tenant_id, medication_id) REFERENCES better_supabase.medications(tenant_id, id);

CREATE INDEX medication_administrations_given_idx ON better_supabase.medication_administrations USING btree (order_id, administered_at)
  WHERE (status = 'given'::text);

CREATE INDEX medication_administrations_order_idx ON better_supabase.medication_administrations USING btree (tenant_id, order_id);

CREATE INDEX medication_administrations_planned_idx ON better_supabase.medication_administrations USING btree (scheduled_at)
  WHERE (status = 'planned'::text);

CREATE UNIQUE INDEX medication_orders_external_idx ON better_supabase.medication_orders USING btree (tenant_id, external_id)
  WHERE (external_id IS NOT NULL);

CREATE INDEX medication_orders_item_idx ON better_supabase.medication_orders USING btree (tenant_id, medication_id);

CREATE INDEX medication_orders_status_idx ON better_supabase.medication_orders USING btree (tenant_id, status);

CREATE INDEX medication_orders_subject_idx ON better_supabase.medication_orders USING btree (subject_type, subject_id);

CREATE UNIQUE INDEX medications_code_idx ON better_supabase.medications USING btree (tenant_id, code_system, code)
  WHERE (code IS NOT NULL);

CREATE INDEX medications_tenant_idx ON better_supabase.medications USING btree (tenant_id, name);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."medication_administrations"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."medication_administrations"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_administrations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.id = medication_administrations.order_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text), false)))))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."medication_administrations"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "medication_administrations_read" ON "better_supabase"."medication_administrations"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.id = medication_administrations.order_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text), false))))));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."medication_orders"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."medication_orders"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_orders"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."medication_orders"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "medication_orders_read" ON "better_supabase"."medication_orders"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id,
    'read'::text), false)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."medications"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."medications"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medications"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."medications"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "medications_read" ON "better_supabase"."medications"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)));

COMMENT ON FUNCTION "better_supabase"."medications_subject_merge"(text, text, text) IS 'better-supabase:subject-merge';

REVOKE ALL ON FUNCTION "api"."archive_medication"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_medication"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_medication"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_medication"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_medication_orders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_medication_orders"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_medications"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_medications"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_missed_medication_administrations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_missed_medication_administrations"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."medication_chart"(text, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."medication_chart"(text, text, timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."medication_orders_of"(text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."medication_orders_of"(text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."pause_medication_order"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pause_medication_order"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."plan_medication_administrations"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."plan_medication_administrations"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."prescribe_medication"(uuid, text, text, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."prescribe_medication"(uuid, text, text, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_as_needed_administration"(uuid, numeric, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_as_needed_administration"(uuid, numeric, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_medication_administration"(uuid, text, numeric, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_medication_administration"(uuid, text, numeric, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_medication"(uuid, text, text, text, text, text, text, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_medication"(uuid, text, text, text, text, text, text, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."stop_medication_order"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stop_medication_order"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_medication_order"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_medication_order"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_medication"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_medication"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_medication"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_medication"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_medication_orders"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_medication_orders"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_medications"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_medications"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_missed_medication_administrations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_missed_medication_administrations"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."medication_chart"(text, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."medication_chart"(text, text, timestamp WITH time zone, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."medication_orders_of"(text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."medication_orders_of"(text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."medications_subject_merge"(text, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."pause_medication_order"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pause_medication_order"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."plan_medication_administrations"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."plan_medication_administrations"(uuid, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."prescribe_medication"(uuid, text, text, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."prescribe_medication"(uuid, text, text, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_as_needed_administration"(uuid, numeric, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_as_needed_administration"(uuid, numeric, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_medication_administration"(uuid, text, numeric, text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_medication_administration"(uuid, text, numeric, text, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_medication"(uuid, text, text, text, text, text, text, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_medication"(uuid, text, text, text, text, text, text, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stop_medication_order"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stop_medication_order"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_medication_order"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_medication_order"(uuid, jsonb) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."medication_administrations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."medication_administrations" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."medication_orders" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."medication_orders" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."medications" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."medications" TO "service_role";
