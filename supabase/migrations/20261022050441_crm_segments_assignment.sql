SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."assignment_queue_members" (
  "queue_id"         uuid                     NOT NULL,
  "tenant_id"        uuid                     NOT NULL,
  "user_id"          uuid                     NOT NULL,
  "weight"           integer                  NOT NULL DEFAULT 1,
  "active"           boolean                  NOT NULL DEFAULT true,
  "credit"           bigint                   NOT NULL DEFAULT 0,
  "assigned_count"   integer                  NOT NULL DEFAULT 0,
  "last_assigned_at" timestamp with time zone,
  CONSTRAINT "assignment_queue_members_pkey" PRIMARY KEY (queue_id, user_id),
  CONSTRAINT "assignment_queue_members_weight_check" CHECK (((weight >= 1) AND (weight <= 100)))
);

ALTER TABLE "better_supabase"."assignment_queue_members"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."assignment_queues" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "name"         text                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "strategy"     text                     NOT NULL DEFAULT 'round_robin'::text,
  "conditions"   jsonb,
  "rank"         integer                  NOT NULL DEFAULT 0,
  "enabled"      boolean                  NOT NULL DEFAULT true,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "assignment_queues_conditions_check" CHECK (((conditions IS NULL) OR (jsonb_typeof(conditions) = 'object'::text))),
  CONSTRAINT "assignment_queues_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "assignment_queues_pkey" PRIMARY KEY (id),
  CONSTRAINT "assignment_queues_strategy_check" CHECK ((strategy = ANY (ARRAY['round_robin'::text, 'weighted'::text]))),
  CONSTRAINT "assignment_queues_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "assignment_queues_tenant_id_name_key" UNIQUE (tenant_id, name)
);

ALTER TABLE "better_supabase"."assignment_queues"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."assignments" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "queue_id"     uuid,
  "subject_type" text                     NOT NULL,
  "subject_id"   text                     NOT NULL,
  "user_id"      uuid,
  "assigned_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "assignments_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."assignments"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."segment_members" (
  "segment_id" uuid                     NOT NULL,
  "tenant_id"  uuid                     NOT NULL,
  "subject_id" text                     NOT NULL,
  "entered_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "segment_members_pkey" PRIMARY KEY (segment_id, subject_id)
);

ALTER TABLE "better_supabase"."segment_members"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."segments" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "name"         text                     NOT NULL,
  "description"  text,
  "subject_type" text                     NOT NULL,
  "conditions"   jsonb                    NOT NULL,
  "member_count" integer                  NOT NULL DEFAULT 0,
  "refreshed_at" timestamp with time zone,
  "created_by"   uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "segments_conditions_check" CHECK ((jsonb_typeof(conditions) = 'object'::text)),
  CONSTRAINT "segments_description_check" CHECK ((length(description) <= 2000)),
  CONSTRAINT "segments_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "segments_pkey" PRIMARY KEY (id),
  CONSTRAINT "segments_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "segments_tenant_id_name_key" UNIQUE (tenant_id, name)
);

ALTER TABLE "better_supabase"."segments"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.assign_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  subject      jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."assign_subject"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.assignment_history (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  max_count    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."assignment_history"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_assignment_queues (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_assignment_queues"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_segment_members (
  segment   uuid,
  after     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_count integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_segment_members"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.refresh_due_segments (
  max_count   integer  DEFAULT NULL::integer,
  stale_after interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."refresh_due_segments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.refresh_segment (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."refresh_segment"($1) $function$;

CREATE OR REPLACE FUNCTION api.remove_assignment_queue (
  queue uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_assignment_queue"($1) $function$;

CREATE OR REPLACE FUNCTION api.remove_segment (
  segment uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_segment"($1) $function$;

CREATE OR REPLACE FUNCTION api.save_assignment_queue (
  tenant uuid,
  queue  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_assignment_queue"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_segment (
  tenant  uuid,
  segment jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_segment"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.segment_get (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."segment_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.segments_list (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."segments_list"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.segments_of (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."segments_of"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_assignment_members (
  queue   uuid,
  members jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_assignment_members"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_subject (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  subject      jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_queue "better_supabase"."assignment_queues";
  v_fields jsonb;
  v_user uuid;
  v_total bigint;
  v_log uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', assign_subject.tenant, 'assignment.assign'), false)) then
    raise exception 'You need assignment.assign to assign records' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  if subject_id is null or length(subject_id) > 200 then
    raise exception 'subject_id must be at most 200 characters' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(assign_subject.subject_type);
  for v_queue in
    select * from "better_supabase"."assignment_queues" x
    where x."tenant_id" = assign_subject.tenant and x."subject_type" = assign_subject.subject_type and x."enabled"
    order by x."rank", x."name"
  loop
    if v_queue."conditions" is not null
      and not "better_supabase"."rule_matches"(v_queue."conditions", coalesce(assign_subject.subject, '{}'::jsonb), v_fields, 'UTC', now()) then
      continue;
    end if;
    perform 1 from "better_supabase"."assignment_queues" x where x."id" = v_queue."id" for update;
    if v_queue."strategy" = 'weighted' then
      select coalesce(sum(z."weight"), 0) into v_total from "better_supabase"."assignment_queue_members" z
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "public"."memberships" mw where mw."organization_id" = v_queue."tenant_id" and mw."user_id" = z."user_id");
      if v_total = 0 then
        continue;
      end if;
      update "better_supabase"."assignment_queue_members" z set "credit" = z."credit" + z."weight"
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "public"."memberships" mw where mw."organization_id" = v_queue."tenant_id" and mw."user_id" = z."user_id");
      select z."user_id" into v_user from "better_supabase"."assignment_queue_members" z
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "public"."memberships" mw where mw."organization_id" = v_queue."tenant_id" and mw."user_id" = z."user_id")
      order by z."credit" desc, z."last_assigned_at" nulls first, z."user_id"
      limit 1;
      update "better_supabase"."assignment_queue_members" z set "credit" = z."credit" - v_total
      where z."queue_id" = v_queue."id" and z."user_id" = v_user;
    else
      select z."user_id" into v_user from "better_supabase"."assignment_queue_members" z
      where z."queue_id" = v_queue."id" and z."active" and exists (select 1 from "public"."memberships" mr where mr."organization_id" = v_queue."tenant_id" and mr."user_id" = z."user_id")
      order by z."last_assigned_at" nulls first, z."user_id"
      limit 1;
      if v_user is null then
        continue;
      end if;
    end if;
    update "better_supabase"."assignment_queue_members" z set "last_assigned_at" = clock_timestamp(), "assigned_count" = z."assigned_count" + 1
    where z."queue_id" = v_queue."id" and z."user_id" = v_user;
    insert into "better_supabase"."assignments" ("tenant_id", "queue_id", "subject_type", "subject_id", "user_id")
    values (v_queue."tenant_id", v_queue."id", v_queue."subject_type", assign_subject.subject_id, v_user)
    returning "id" into v_log;
    perform "better_supabase".emit_event('subject.assigned', jsonb_build_object('organizationId', v_queue."tenant_id", 'queueId', v_queue."id", 'subjectType', v_queue."subject_type", 'subjectId', assign_subject.subject_id, 'userId', v_user, 'strategy', v_queue."strategy"), 'assignment-queues/' || v_queue."id"::text, (v_queue."tenant_id"::text)::text, 'subject.assigned:' || v_log::text, 'better-supabase/assignment');
    return jsonb_build_object('queueId', v_queue."id", 'userId', v_user, 'strategy', v_queue."strategy");
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.assignment_history (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  max_count    integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(better_supabase.can('tenant', assignment_history.tenant, 'assignment.read'), false) then
    raise exception 'You need assignment.read to read assignments' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('queueId', y."queue_id", 'userId', y."user_id", 'assignedAt', y."assigned_at") order by y."assigned_at" desc, y."id")
    from (
      select x.* from "better_supabase"."assignments" x
      where x."tenant_id" = assignment_history.tenant and x."subject_type" = assignment_history.subject_type
        and x."subject_id" = assignment_history.subject_id
      order by x."assigned_at" desc, x."id"
      limit least(greatest(coalesce(assignment_history.max_count, 20), 1), 200)
    ) y
  ), '[]'::jsonb);
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
    ('user', 'better_supabase.attachments', '"better_supabase"."attachments"', 'uploaded_by', true, '{}'::text[], true),
    ('user', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'owner_id', true, array['search_tsv']::text[], true),
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
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', false, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.documents', '"better_supabase"."documents"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'actor', true, '{}'::text[], true),
    ('user', 'better_supabase.carts', '"better_supabase"."carts"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.forms', '"better_supabase"."forms"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_versions', '"better_supabase"."form_versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.form_submissions', '"better_supabase"."form_submissions"', 'respondent_id', true, '{}'::text[], true),
    ('user', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.engagements', '"better_supabase"."engagements"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversations', '"better_supabase"."conversations"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.messages', '"better_supabase"."messages"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'edited_by', true, '{}'::text[], true),
    ('user', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.channels', '"better_supabase"."channels"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'user_id', true, array['credential_ref']::text[], true),
    ('user', 'better_supabase.assignment_queue_members', '"better_supabase"."assignment_queue_members"', 'user_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'organization_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_domains', '"better_supabase"."organization_domains"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.onboarding_progress', '"better_supabase"."onboarding_progress"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'organization_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.teams', '"better_supabase"."teams"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.team_members', '"better_supabase"."team_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tags', '"better_supabase"."tags"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.taggings', '"better_supabase"."taggings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_history', '"better_supabase"."status_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.status_stages', '"better_supabase"."status_stages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.subject_lifecycles', '"better_supabase"."subject_lifecycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_definitions', '"better_supabase"."field_definitions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.field_values', '"better_supabase"."field_values"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.share_links', '"better_supabase"."share_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.recurrence_rules', '"better_supabase"."recurrence_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reminders', '"better_supabase"."reminders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.collections', '"better_supabase"."collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.collection_products', '"better_supabase"."collection_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.storefronts', '"better_supabase"."storefronts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.search_documents', '"better_supabase"."search_documents"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.metric_points', '"better_supabase"."metric_points"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.calendars', '"better_supabase"."calendars"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'tenant_id', false, '{}'::text[], true),
    ('organization', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_resources', '"better_supabase"."booking_resources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_availability', '"better_supabase"."booking_availability"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_exceptions', '"better_supabase"."booking_exceptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.booking_services', '"better_supabase"."booking_services"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bookings', '"better_supabase"."bookings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.versions', '"better_supabase"."versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.reactions', '"better_supabase"."reactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inventory_locations', '"better_supabase"."inventory_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_levels', '"better_supabase"."stock_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_movements', '"better_supabase"."stock_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_reservations', '"better_supabase"."stock_reservations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfers', '"better_supabase"."stock_transfers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_transfer_lines', '"better_supabase"."stock_transfer_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_orders', '"better_supabase"."purchase_orders"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.purchase_order_lines', '"better_supabase"."purchase_order_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.time_entries', '"better_supabase"."time_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.timesheets', '"better_supabase"."timesheets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.service_principals', '"better_supabase"."service_principals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.templates', '"better_supabase"."templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.template_applications', '"better_supabase"."template_applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deals', '"better_supabase"."deals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_contacts', '"better_supabase"."deal_contacts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deal_lines', '"better_supabase"."deal_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_items', '"better_supabase"."work_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_projects', '"better_supabase"."work_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.iterations', '"better_supabase"."iterations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.jobs', '"better_supabase"."jobs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.applications', '"better_supabase"."applications"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.interviews', '"better_supabase"."interviews"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_payments', '"better_supabase"."invoice_payments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_members', '"better_supabase"."conversation_members"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.messages', '"better_supabase"."messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_edits', '"better_supabase"."message_edits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.thread_reads', '"better_supabase"."thread_reads"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.assignments', '"better_supabase"."assignments"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.evaluate_segment (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
  v_fields jsonb;
  v_now timestamptz := now();
  v_ids text[];
  v_entered text[];
  v_left text[];
  v_id text;
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = evaluate_segment.segment for update;
  if v_row."id" is null then
    return null;
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_row."subject_type");
  if v_row."subject_type" = 'message' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."messages" s
      where s."tenant_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'conversation' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."conversations" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'channel' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."channels" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'company' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."companies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'person' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."people" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'deal' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."deals" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'engagement' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."engagements" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_item' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_items" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'employee' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."employees" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."products" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product_variant' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."product_variants" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'calendar_event' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."calendar_events" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'document' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."documents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'customer' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."customers" s
      where s."organization_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'drive_node' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."drive_nodes" s
      where s."tenant_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'application' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."applications" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'project' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."projects" s
      where s."organization_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'task' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."tasks" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  else
    raise exception 'The segment''s subject type is not registered in config.subjects' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  if cardinality(v_ids) > 10000 then
    raise exception 'A segment holds at most 10000 records; narrow its conditions' using errcode = '54000', hint = 'SEGMENT_TOO_LARGE';
  end if;
  with gone as (
    delete from "better_supabase"."segment_members" y
    where y."segment_id" = v_row."id" and not (y."subject_id" = any (v_ids))
    returning y."subject_id" as id
  ), added as (
    insert into "better_supabase"."segment_members" ("segment_id", "tenant_id", "subject_id", "entered_at")
    select v_row."id", v_row."tenant_id", z, v_now from unnest(v_ids) z
    on conflict do nothing
    returning "subject_id" as id
  )
  select coalesce((select array_agg(g.id order by g.id) from gone g), '{}'),
    coalesce((select array_agg(a.id order by a.id) from added a), '{}')
  into v_left, v_entered;
  foreach v_id in array v_entered loop
    perform "better_supabase".emit_event('segment.entered', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.entered:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  foreach v_id in array v_left loop
    perform "better_supabase".emit_event('segment.left', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.left:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  update "better_supabase"."segments" x set "member_count" = cardinality(v_ids), "refreshed_at" = v_now
  where x."id" = v_row."id";
  return jsonb_build_object('entered', cardinality(v_entered), 'left', cardinality(v_left), 'memberCount', cardinality(v_ids));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_assignment_queues (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(better_supabase.can('tenant', list_assignment_queues.tenant, 'assignment.read'), false) then
    raise exception 'You need assignment.read to list assignment queues' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'subjectType', x."subject_type", 'strategy', x."strategy", 'conditions', x."conditions", 'rank', x."rank", 'enabled', x."enabled", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z."user_id", 'weight', z."weight", 'active', z."active", 'assignedCount', z."assigned_count", 'lastAssignedAt', z."last_assigned_at") order by z."user_id")
      from "better_supabase"."assignment_queue_members" z where z."queue_id" = x."id"
    ), '[]'::jsonb)) order by x."subject_type", x."rank", x."name")
    from "better_supabase"."assignment_queues" x
    where x."tenant_id" = list_assignment_queues.tenant
      and (list_assignment_queues.subject_type is null or x."subject_type" = list_assignment_queues.subject_type)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_segment_members (
  segment   uuid,
  after     timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_count integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = list_segment_members.segment;
  if v_row."id" is null or not coalesce(better_supabase.can('tenant', v_row."tenant_id", 'segments.read'), false)
    or not (case v_row."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'engagements.read'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'work_items.read'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'calendar.read'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'documents.read'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    else true
  end) then
    raise exception 'No segment you can read has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('subjectId', y."subject_id", 'enteredAt', y."entered_at") order by y."entered_at" desc, y."subject_id")
    from (
      select z.* from "better_supabase"."segment_members" z
      where z."segment_id" = v_row."id"
        and (list_segment_members.after is null or z."entered_at" < list_segment_members.after)
      order by z."entered_at" desc, z."subject_id"
      limit least(greatest(coalesce(list_segment_members.max_count, 50), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refresh_due_segments (
  max_count   integer  DEFAULT NULL::integer,
  stale_after interval DEFAULT NULL::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_segment uuid;
  v_result jsonb;
  v_count integer := 0;
  v_entered integer := 0;
  v_left integer := 0;
begin
  for v_segment in
    select x."id" from "better_supabase"."segments" x
    where x."refreshed_at" is null
      or x."refreshed_at" < now() - coalesce(refresh_due_segments.stale_after, interval '1 hour')
    order by x."refreshed_at" nulls first, x."id"
    limit least(greatest(coalesce(refresh_due_segments.max_count, 25), 1), 500)
  loop
    v_result := "better_supabase"."evaluate_segment"(v_segment);
    v_count := v_count + 1;
    v_entered := v_entered + (v_result ->> 'entered')::integer;
    v_left := v_left + (v_result ->> 'left')::integer;
  end loop;
  return jsonb_build_object('segments', v_count, 'entered', v_entered, 'left', v_left);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.refresh_segment (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."segments" x where x."id" = refresh_segment.segment;
  if v_tenant is null then
    raise exception 'No segment has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'segments.edit'), false)) then
    raise exception 'You need segments.edit to refresh a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  return "better_supabase"."evaluate_segment"(refresh_segment.segment);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_assignment_queue (
  queue uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."assignment_queues" x where x."id" = remove_assignment_queue.queue;
  if v_tenant is null then
    return false;
  end if;
  if not coalesce(better_supabase.can('tenant', v_tenant, 'assignment.manage'), false) then
    raise exception 'You need assignment.manage to remove an assignment queue' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."assignment_queues" x where x."id" = remove_assignment_queue.queue;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_segment (
  segment uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."segments" x where x."id" = remove_segment.segment;
  if v_row."id" is null then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'segments.edit'), false)) then
    raise exception 'You need segments.edit to remove a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  delete from "better_supabase"."segments" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('segment.removed', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.removed',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.role_permissions (
  role text
)
  RETURNS text[]
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case role
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'tags.read', 'tags.apply', 'tags.manage',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share', 'ai_chat.admin',
      'ai.read', 'ai.create', 'ai.share', 'ai.admin',
      'attachments.read', 'attachments.upload', 'attachments.manage', 'sso.manage',
      'waitlist.manage', 'teams.read', 'teams.manage', 'catalog.read', 'catalog.manage',
      'inventory.read', 'inventory.manage', 'inventory.reserve', 'inventory.purchase',
      'orders.read', 'orders.manage', 'promotions.read', 'promotions.manage', 'custom_fields.read',
      'custom_fields.manage', 'custom_fields.sensitive.read', 'share_links.read',
      'share_links.create', 'reminders.read', 'reminders.manage', 'imports.manage',
      'views.read', 'views.share', 'relations.read', 'relations.manage', 'bulk.run',
      'calendar.read', 'calendar.write', 'calendar.manage', 'bookings.read', 'bookings.create',
      'bookings.manage', 'versions.read', 'versions.create', 'versions.restore',
      'versions.manage', 'trash.read', 'trash.create', 'trash.restore', 'trash.manage',
      'reactions.read', 'reactions.create', 'reactions.manage', 'approvals.read',
      'approvals.request', 'approvals.manage', 'access_requests.read', 'access_requests.create',
      'access_requests.manage', 'documents.read', 'documents.write', 'documents.manage',
      'drive.read', 'drive.create', 'drive.manage', 'forms.read', 'forms.submit',
      'forms.review', 'forms.manage', 'templates.read', 'templates.apply', 'templates.manage',
      'time_tracking.read', 'time_tracking.track', 'time_tracking.approve', 'time_tracking.manage',
      'service_principals.read', 'service_principals.manage', 'pipelines.read',
      'pipelines.manage', 'parties.read', 'parties.write', 'parties.manage', 'engagements.read',
      'engagements.write', 'engagements.manage', 'deals.read', 'deals.write', 'deals.manage',
      'work_items.read', 'work_items.write', 'work_items.manage', 'quotes.read',
      'quotes.write', 'quotes.manage', 'invoices.read', 'invoices.write', 'invoices.manage',
      'sla.read', 'sla.manage', 'targets.read', 'targets.manage', 'hiring.read',
      'hiring.write', 'hiring.manage', 'employees.read', 'employees.write', 'employees.view_sensitive',
      'webhooks.read', 'webhooks.manage', 'organization.export',
      'rules.read', 'rules.edit', 'rules.publish', 'rules.admin',
      'messages.read', 'messages.send', 'messages.moderate',
      'channels.create', 'channels.manage',
      'mail.read', 'mail.connect', 'mail.send', 'mail.manage',
      'segments.read', 'segments.edit',
      'assignment.read', 'assignment.manage', 'assignment.assign'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'tags.read', 'tags.apply', 'onboarding.read', 'usage.read', 'usage.record', 'search.read', 'metrics.read',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'inbox.read', 'inbox.reply',
      'ai_chat.read', 'ai_chat.create', 'ai_chat.share',
      'ai.read', 'ai.create', 'ai.share',
      'attachments.read', 'attachments.upload', 'teams.read', 'catalog.read', 'inventory.read',
      'orders.read', 'promotions.read', 'custom_fields.read', 'share_links.read',
      'share_links.create', 'reminders.read', 'reminders.manage', 'views.read',
      'views.share', 'relations.read', 'relations.manage', 'calendar.read', 'calendar.write',
      'bookings.read', 'bookings.create', 'versions.read', 'versions.create', 'trash.read',
      'trash.create', 'trash.restore', 'reactions.read', 'reactions.create', 'approvals.read',
      'approvals.request', 'access_requests.read', 'access_requests.create', 'documents.read',
      'documents.write', 'drive.read', 'drive.create', 'forms.read', 'forms.submit',
      'templates.read', 'templates.apply', 'time_tracking.read', 'time_tracking.track',
      'pipelines.read', 'parties.read', 'parties.write', 'engagements.read', 'engagements.write',
      'deals.read', 'deals.write', 'work_items.read', 'work_items.write', 'quotes.read',
      'quotes.write', 'invoices.read', 'sla.read', 'targets.read', 'hiring.read',
      'employees.read', 'rules.read', 'messages.read', 'messages.send', 'channels.create',
      'mail.read', 'mail.connect', 'mail.send', 'segments.read', 'assignment.read'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_assignment_queue (
  tenant uuid,
  queue  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_old "better_supabase"."assignment_queues";
  v_row "better_supabase"."assignment_queues";
  v_type text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_assignment_queue.tenant, 'assignment.manage'), false) then
    raise exception 'You need assignment.manage to change assignment queues' using errcode = '42501', hint = 'ASSIGNMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(queue) is distinct from 'object' then
    raise exception 'queue must be an object' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_id := nullif(queue ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."assignment_queues" x
    where x."id" = v_id and x."tenant_id" = save_assignment_queue.tenant for update;
    if v_old."id" is null then
      raise exception 'No assignment queue in this organization has this id' using errcode = 'P0002', hint = 'ASSIGNMENT_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(queue ->> 'subjectType', v_old."subject_type");
  if v_type is null or v_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'A queue needs a subject type' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  v_conditions := case when queue ? 'conditions' then nullif(queue -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'ASSIGNMENT_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."assignment_queues" ("tenant_id", "name", "subject_type", "strategy", "conditions", "rank", "enabled")
    values (save_assignment_queue.tenant, trim(queue ->> 'name'), v_type, coalesce(queue ->> 'strategy', 'round_robin'),
      v_conditions, coalesce((queue ->> 'rank')::integer, 0), coalesce((queue ->> 'enabled')::boolean, true))
    returning * into v_row;
  else
    update "better_supabase"."assignment_queues" x set
      "name" = coalesce(trim(queue ->> 'name'), x."name"),
      "subject_type" = v_type,
      "strategy" = coalesce(queue ->> 'strategy', x."strategy"),
      "conditions" = v_conditions,
      "rank" = coalesce((queue ->> 'rank')::integer, x."rank"),
      "enabled" = coalesce((queue ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'subjectType', v_row."subject_type", 'strategy', v_row."strategy", 'conditions', v_row."conditions", 'rank', v_row."rank", 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z."user_id", 'weight', z."weight", 'active', z."active", 'assignedCount', z."assigned_count", 'lastAssignedAt', z."last_assigned_at") order by z."user_id")
      from "better_supabase"."assignment_queue_members" z where z."queue_id" = v_row."id"
    ), '[]'::jsonb));
exception
  when unique_violation then
    raise exception 'Another assignment queue in this organization has this name' using errcode = '23505', hint = 'ASSIGNMENT_NAME_TAKEN';
  when check_violation or not_null_violation then
    raise exception 'A queue needs a name of at most 200 characters and a strategy of round_robin or weighted' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_segment (
  tenant  uuid,
  segment jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_old "better_supabase"."segments";
  v_row "better_supabase"."segments";
  v_type text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_segment.tenant, 'segments.edit'), false) then
    raise exception 'You need segments.edit to save a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(segment) is distinct from 'object' then
    raise exception 'segment must be an object' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_id := nullif(segment ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."segments" x
    where x."id" = v_id and x."tenant_id" = save_segment.tenant for update;
    if v_old."id" is null then
      raise exception 'No segment in this organization has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
    end if;
    if segment ? 'subjectType' and segment ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A segment''s subject type can''t change' using errcode = '22023', hint = 'SEGMENT_INVALID';
    end if;
  end if;
  v_type := coalesce(v_old."subject_type", segment ->> 'subjectType');
  if v_type is null or v_type not in ('message', 'conversation', 'channel', 'company', 'person', 'deal', 'engagement', 'work_item', 'employee', 'product', 'product_variant', 'calendar_event', 'document', 'customer', 'drive_node', 'application', 'project', 'task') then
    raise exception 'subjectType must be a type in config.subjects' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  v_name := coalesce(nullif(trim(segment ->> 'name'), ''), v_old."name");
  if v_name is null or length(v_name) > 200 then
    raise exception 'A segment needs a name of at most 200 characters' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_description := case when segment ? 'description' then nullif(trim(segment ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(segment -> 'conditions', v_old."conditions");
  if jsonb_typeof(v_conditions) is distinct from 'object' then
    raise exception 'A segment needs conditions, a filter tree' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_type);
  if v_fields = '{}'::jsonb then
    raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SEGMENT_FIELDS_MISSING';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if v_old."id" is null then
    insert into "better_supabase"."segments" ("tenant_id", "name", "description", "subject_type", "conditions", "created_by")
    values (save_segment.tenant, v_name, v_description, v_type, v_conditions, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'conditions', v_old."conditions", 'memberCount', v_old."member_count", 'refreshedAt', v_old."refreshed_at", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."segments" x set
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "refreshed_at" = case when x."conditions" = v_conditions then x."refreshed_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('segment.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.saved',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'conditions', v_row."conditions", 'memberCount', v_row."member_count", 'refreshedAt', v_row."refreshed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'Another segment in this organization has this name' using errcode = '23505', hint = 'SEGMENT_NAME_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.segment_get (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."segments" x
  where x."id" = segment_get.segment and coalesce(better_supabase.can('tenant', x."tenant_id", 'segments.read'), false)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.segments_list (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(better_supabase.can('tenant', segments_list.tenant, 'segments.read'), false) then
    raise exception 'You need segments.read to list segments' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'conditions', x."conditions", 'memberCount', x."member_count", 'refreshedAt', x."refreshed_at", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."name")
    from "better_supabase"."segments" x
    where x."tenant_id" = segments_list.tenant
      and (segments_list.subject_type is null or x."subject_type" = segments_list.subject_type)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.segments_of (
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'name', x."name", 'enteredAt', y."entered_at") order by x."name"), '[]'::jsonb)
  from "better_supabase"."segment_members" y
  join "better_supabase"."segments" x on x."id" = y."segment_id"
  where x."subject_type" = segments_of.subject_type and y."subject_id" = segments_of.subject_id
    and coalesce(better_supabase.can('tenant', x."tenant_id", 'segments.read'), false)
    and (case x."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'product' then coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'document' then coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false)
    when 'application' then coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    else true
  end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_assignment_members (
  queue   uuid,
  members jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_queue "better_supabase"."assignment_queues";
  v_item jsonb;
  v_users uuid[] := '{}';
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_queue from "better_supabase"."assignment_queues" x where x."id" = set_assignment_members.queue for update;
  if v_queue."id" is null or not coalesce(better_supabase.can('tenant', v_queue."tenant_id", 'assignment.manage'), false) then
    raise exception 'No assignment queue you can manage has this id' using errcode = 'P0002', hint = 'ASSIGNMENT_NOT_FOUND';
  end if;
  if jsonb_typeof(members) is distinct from 'array' or jsonb_array_length(members) > 200 then
    raise exception 'members must be an array of at most 200 entries' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
  end if;
  for v_item in select x.value from jsonb_array_elements(members) x loop
    v_user := nullif(v_item ->> 'userId', '')::uuid;
    if v_user is null or not exists (select 1 from "public"."memberships" mm where mm."organization_id" = v_queue."tenant_id" and mm."user_id" = v_user) then
      raise exception 'Every member must be a member of the queue''s organization' using errcode = '22023', hint = 'ASSIGNMENT_MEMBER_INVALID';
    end if;
    v_users := v_users || v_user;
    insert into "better_supabase"."assignment_queue_members" ("queue_id", "tenant_id", "user_id", "weight", "active")
    values (v_queue."id", v_queue."tenant_id", v_user, coalesce((v_item ->> 'weight')::integer, 1), coalesce((v_item ->> 'active')::boolean, true))
    on conflict ("queue_id", "user_id") do update set
      "weight" = excluded."weight",
      "active" = excluded."active";
  end loop;
  delete from "better_supabase"."assignment_queue_members" z where z."queue_id" = v_queue."id" and not (z."user_id" = any (v_users));
  return jsonb_build_object('id', v_queue."id", 'organizationId', v_queue."tenant_id", 'name', v_queue."name", 'subjectType', v_queue."subject_type", 'strategy', v_queue."strategy", 'conditions', v_queue."conditions", 'rank', v_queue."rank", 'enabled', v_queue."enabled", 'createdAt', v_queue."created_at", 'updatedAt', v_queue."updated_at", 'members', coalesce((
      select jsonb_agg(jsonb_build_object('userId', z."user_id", 'weight', z."weight", 'active', z."active", 'assignedCount', z."assigned_count", 'lastAssignedAt', z."last_assigned_at") order by z."user_id")
      from "better_supabase"."assignment_queue_members" z where z."queue_id" = v_queue."id"
    ), '[]'::jsonb));
exception when check_violation then
  raise exception 'A member''s weight is between 1 and 100' using errcode = '22023', hint = 'ASSIGNMENT_INVALID';
end;
$function$;

ALTER TABLE "better_supabase"."assignment_queue_members"
  ADD CONSTRAINT "assignment_queue_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."assignment_queue_members"
  ADD CONSTRAINT "assignment_queue_members_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES better_supabase.assignment_queues(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."assignments"
  ADD CONSTRAINT "assignments_queue_id_fkey" FOREIGN KEY (queue_id) REFERENCES better_supabase.assignment_queues(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."assignments"
  ADD CONSTRAINT "assignments_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."segments"
  ADD CONSTRAINT "segments_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."segment_members"
  ADD CONSTRAINT "segment_members_segment_id_fkey" FOREIGN KEY (segment_id) REFERENCES better_supabase.segments(id) ON DELETE CASCADE;

CREATE INDEX assignment_queue_members_user_idx ON better_supabase.assignment_queue_members USING btree (user_id);

CREATE INDEX assignment_queues_order_idx ON better_supabase.assignment_queues USING btree (tenant_id, subject_type, rank)
  WHERE enabled;

CREATE INDEX assignments_queue_idx ON better_supabase.assignments USING btree (queue_id)
  WHERE (queue_id IS NOT NULL);

CREATE INDEX assignments_subject_idx ON better_supabase.assignments USING btree (tenant_id, subject_type, subject_id, assigned_at DESC);

CREATE INDEX assignments_user_idx ON better_supabase.assignments USING btree (user_id)
  WHERE (user_id IS NOT NULL);

CREATE INDEX segment_members_subject_idx ON better_supabase.segment_members USING btree (tenant_id, subject_id);

CREATE INDEX segments_created_by_idx ON better_supabase.segments USING btree (created_by)
  WHERE (created_by IS NOT NULL);

CREATE INDEX segments_due_idx ON better_supabase.segments USING btree (refreshed_at NULLS FIRST);

CREATE POLICY "assignment_queue_members_read" ON "better_supabase"."assignment_queue_members"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('assignment.read'::text) AS tenant_ids_with)));

CREATE POLICY "assignment_queues_read" ON "better_supabase"."assignment_queues"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('assignment.read'::text) AS tenant_ids_with)));

CREATE POLICY "assignments_read" ON "better_supabase"."assignments"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('assignment.read'::text) AS tenant_ids_with)));

CREATE POLICY "segment_members_read" ON "better_supabase"."segment_members"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('segments.read'::text) AS tenant_ids_with)));

CREATE POLICY "segments_read" ON "better_supabase"."segments"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('segments.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."assign_subject"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."assign_subject"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."assignment_history"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."assignment_history"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_assignment_queues"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_assignment_queues"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_segment_members"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_segment_members"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."refresh_due_segments"(integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."refresh_due_segments"(integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."refresh_segment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."refresh_segment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_assignment_queue"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_assignment_queue"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_segment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_segment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_assignment_queue"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_assignment_queue"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_segment"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_segment"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."segment_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."segment_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."segments_list"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."segments_list"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."segments_of"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."segments_of"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_assignment_members"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_assignment_members"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."assign_subject"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."assign_subject"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."assignment_history"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."assignment_history"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."evaluate_segment"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."list_assignment_queues"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_assignment_queues"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_segment_members"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_segment_members"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."refresh_due_segments"(integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."refresh_due_segments"(integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."refresh_segment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."refresh_segment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_assignment_queue"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_assignment_queue"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_segment"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_segment"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_assignment_queue"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_assignment_queue"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_segment"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_segment"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."segment_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."segment_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."segments_list"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."segments_list"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."segments_of"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."segments_of"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_assignment_members"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_assignment_members"(uuid, jsonb) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."assignment_queue_members" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."assignment_queue_members" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."assignment_queues" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."assignment_queues" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."assignments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."assignments" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."segment_members" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."segment_members" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."segments" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."segments" TO "service_role";
