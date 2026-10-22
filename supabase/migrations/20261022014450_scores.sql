SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."score_model_versions" (
  "model_id"  uuid                     NOT NULL,
  "version"   integer                  NOT NULL,
  "tenant_id" uuid                     NOT NULL,
  "rules"     jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "metrics"   jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "bands"     jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "saved_by"  uuid,
  "saved_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "score_model_versions_bands_check" CHECK ((jsonb_typeof(bands) = 'array'::text)),
  CONSTRAINT "score_model_versions_metrics_check" CHECK ((jsonb_typeof(metrics) = 'array'::text)),
  CONSTRAINT "score_model_versions_pkey" PRIMARY KEY (model_id, VERSION),
  CONSTRAINT "score_model_versions_rules_check" CHECK ((jsonb_typeof(rules) = 'array'::text))
);

ALTER TABLE "better_supabase"."score_model_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."score_models" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid                     NOT NULL,
  "key"          text                     NOT NULL,
  "name"         text                     NOT NULL,
  "description"  text,
  "subject_type" text                     NOT NULL,
  "rules"        jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "metrics"      jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "bands"        jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "enabled"      boolean                  NOT NULL DEFAULT true,
  "version"      integer                  NOT NULL DEFAULT 1,
  "created_by"   uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "score_models_bands_check" CHECK ((jsonb_typeof(bands) = 'array'::text)),
  CONSTRAINT "score_models_description_check" CHECK (((description IS NULL) OR (length(description) <= 2000))),
  CONSTRAINT "score_models_key_check" CHECK ((key ~ '^[a-z][a-z0-9_-]{0,62}$'::text)),
  CONSTRAINT "score_models_metrics_check" CHECK ((jsonb_typeof(metrics) = 'array'::text)),
  CONSTRAINT "score_models_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "score_models_pkey" PRIMARY KEY (id),
  CONSTRAINT "score_models_rules_check" CHECK ((jsonb_typeof(rules) = 'array'::text)),
  CONSTRAINT "score_models_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "score_models_tenant_id_key_key" UNIQUE (tenant_id, key)
);

ALTER TABLE "better_supabase"."score_models"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."scores" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "model_id"      uuid                     NOT NULL,
  "model_version" integer                  NOT NULL,
  "subject_type"  text                     NOT NULL,
  "subject_id"    text                     NOT NULL,
  "score"         numeric                  NOT NULL,
  "band"          text,
  "breakdown"     jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "is_current"    boolean                  NOT NULL DEFAULT true,
  "computed_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "scores_breakdown_check" CHECK ((jsonb_typeof(breakdown) = 'object'::text)),
  CONSTRAINT "scores_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."scores"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.compute_score (
  tenant       uuid,
  model_key    text,
  subject_type text,
  subject_id   text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."compute_score"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.delete_score_model (
  model_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_score_model"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_score_model"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_score_models (
  tenant       uuid,
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_score_models"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_score_model (
  tenant uuid,
  model  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_score_model"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.score_history (
  tenant       uuid,
  model_key    text,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."score_history"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.subject_scores (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_scores"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.top_scores (
  tenant    uuid,
  model_key text,
  band      text    DEFAULT NULL::text,
  min_score numeric DEFAULT NULL::numeric,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."top_scores"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION better_supabase.compute_score (
  tenant       uuid,
  model_key    text,
  subject_type text,
  subject_id   text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_model "better_supabase"."score_models";
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current "better_supabase"."scores";
  v_row "better_supabase"."scores";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', compute_score.tenant, 'scores.compute'), false)) then
    raise exception 'not allowed to compute scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  select * into v_model from "better_supabase"."score_models" x where x."tenant_id" = compute_score.tenant and x."key" = compute_score.model_key;
  if not found then
    raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
  end if;
  if not v_model."enabled" then
    raise exception 'the score model is turned off' using errcode = '55000', hint = 'SCORES_MODEL_DISABLED';
  end if;
  if compute_score.subject_type is distinct from v_model."subject_type" then
    raise exception 'the score model scores another subject type' using errcode = '22023', hint = 'SCORES_SUBJECT_MISMATCH';
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    raise exception 'subject must be an object and subject_id set' using errcode = '22023', hint = 'SCORES_SUBJECT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_model."subject_type");
  for v_entry in select x.value from jsonb_array_elements(v_model."rules") x loop
    v_matched := coalesce("better_supabase"."rule_matches"(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model."metrics") x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := coalesce((select y."score" from "better_supabase"."reaction_scores" y where y."tenant_id" = compute_score.tenant and y."subject_type" = compute_score.subject_type and y."subject_id" = compute_score.subject_id), 0);
    else
      v_value := "better_supabase"."rule_numeric"(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model."bands") x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from "better_supabase"."scores" x
  where x."model_id" = v_model."id" and x."subject_type" = compute_score.subject_type
    and x."subject_id" = compute_score.subject_id and x."is_current"
  for update;
  if found and v_current."score" = v_total and v_current."band" is not distinct from v_band
    and v_current."model_version" = v_model."version" and v_current."breakdown" = v_breakdown then
    return jsonb_build_object('id', v_current."id", 'organizationId', v_current."tenant_id", 'modelId', v_current."model_id", 'modelKey', v_model."key", 'modelVersion', v_current."model_version", 'subjectType', v_current."subject_type", 'subjectId', v_current."subject_id", 'score', v_current."score", 'band', v_current."band", 'breakdown', v_current."breakdown", 'current', v_current."is_current", 'computedAt', v_current."computed_at") || jsonb_build_object('changed', false);
  end if;
  update "better_supabase"."scores" x set "is_current" = false where x."id" = v_current."id";
  insert into "better_supabase"."scores" ("tenant_id", "model_id", "model_version", "subject_type", "subject_id", "score", "band", "breakdown", "computed_at")
  values (compute_score.tenant, v_model."id", v_model."version", compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  perform "better_supabase".emit_event('score.changed', jsonb_build_object('organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'previousScore', v_current."score", 'band', v_row."band", 'previousBand', v_current."band"), 'scores/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'modelId', v_row."model_id", 'modelKey', v_model."key", 'modelVersion', v_row."model_version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'score', v_row."score", 'band', v_row."band", 'breakdown', v_row."breakdown", 'current', v_row."is_current", 'computedAt', v_row."computed_at") || jsonb_build_object('changed', true);
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
    ('user', 'better_supabase.comments', '"better_supabase"."comments"', 'author_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.conversation_participants', '"better_supabase"."conversation_participants"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.conversation_reads', '"better_supabase"."conversation_reads"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ledger_accounts', '"better_supabase"."ledger_accounts"', 'owner_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.comments', '"better_supabase"."comments"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.conversations', '"better_supabase"."conversations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.conversation_events', '"better_supabase"."conversation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_messages', '"better_supabase"."inbox_messages"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.message_deliveries', '"better_supabase"."message_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.inbox_mentions', '"better_supabase"."inbox_mentions"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.reaction_scores', '"better_supabase"."reaction_scores"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.access_requests', '"better_supabase"."access_requests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.documents', '"better_supabase"."documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_updates', '"better_supabase"."document_updates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_snapshots', '"better_supabase"."document_snapshots"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.targets', '"better_supabase"."targets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rules', '"better_supabase"."rules"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_versions', '"better_supabase"."rule_versions"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_locations', '"better_supabase"."asset_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.assets', '"better_supabase"."assets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.asset_assignments', '"better_supabase"."asset_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_models', '"better_supabase"."score_models"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scores', '"better_supabase"."scores"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_score_model (
  model_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."score_models";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."score_models" x where x."id" = delete_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  delete from "better_supabase"."score_models" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('score_model.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.deleted',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'deleted score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_score_model (
  model_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."score_models";
begin
  select * into v_row from "better_supabase"."score_models" x where x."id" = get_score_model.model_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'scores.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y."version", 'rules', y."rules", 'metrics', y."metrics", 'bands', y."bands", 'savedBy', y."saved_by", 'savedAt', y."saved_at") order by y."version" desc)
    from "better_supabase"."score_model_versions" y where y."model_id" = v_row."id"
  ), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_score_models (
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
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_score_models.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'key', x."key", 'name', x."name", 'description', x."description", 'subjectType', x."subject_type", 'rules', x."rules", 'metrics', x."metrics", 'bands', x."bands", 'enabled', x."enabled", 'version', x."version", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."key")
    from "better_supabase"."score_models" x
    where x."tenant_id" = list_score_models.tenant
      and (list_score_models.subject_type is null or x."subject_type" = list_score_models.subject_type)
  ), '[]'::jsonb);
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
      'assets.read', 'assets.manage', 'assets.assign',
      'scores.read', 'scores.manage', 'scores.compute'
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
      'employees.read', 'rules.read', 'assets.read', 'scores.read'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_score_model (
  tenant uuid,
  model  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."score_models";
  v_row "better_supabase"."score_models";
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_score_model.tenant, 'scores.manage'), false)) then
    raise exception 'not allowed to manage score models' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    raise exception 'model must be an object' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."score_models" x where x."id" = v_id and x."tenant_id" = save_score_model.tenant for update;
    if v_old."id" is null then
      raise exception 'score model not found' using errcode = 'P0002', hint = 'SCORES_MODEL_NOT_FOUND';
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'the score model changed since it was read' using errcode = '40001', hint = 'SCORES_MODEL_CONFLICT';
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'a score model''s subject type can''t change' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end if;
  v_key := coalesce(v_old."key", model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old."name");
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old."description" end;
  v_subject_type := coalesce(v_old."subject_type", model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old."rules", '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old."metrics", '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old."bands", '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old."enabled", true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'a score model needs a key such as lead or health' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'a score model needs a name of at most 200 characters' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'a score model needs a subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > 100 then
    raise exception 'rules must be an array of at most 100 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > 50 then
    raise exception 'metrics must be an array of at most 50 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > 10 then
    raise exception 'bands must be an array of at most 10 entries' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      raise exception 'every rule needs an id, conditions and a number of points' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SCORES_SUBJECT_UNKNOWN';
    end if;
    perform "better_supabase"."rule_check"(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ('field', 'votes')
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      raise exception 'every metric needs an id, a source (field or votes), and a numeric weight and cap' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      raise exception 'a field metric names a number field of the subject type' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      raise exception 'every band needs a label and a min score' using errcode = '22023', hint = 'SCORES_MODEL_INVALID';
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old."id" is null then
    if exists (select 1 from "better_supabase"."score_models" x where x."tenant_id" = save_score_model.tenant and x."key" = v_key) then
      raise exception 'a score model with this key already exists' using errcode = '23505', hint = 'SCORES_MODEL_KEY_TAKEN';
    end if;
    insert into "better_supabase"."score_models" ("tenant_id", "key", "name", "description", "subject_type", "rules", "metrics", "bands", "enabled", "created_by")
    values (save_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."rules" = v_rules and v_old."metrics" = v_metrics
    and v_old."bands" = v_bands and v_old."enabled" = v_enabled then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'key', v_old."key", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'rules', v_old."rules", 'metrics', v_old."metrics", 'bands', v_old."bands", 'enabled', v_old."enabled", 'version', v_old."version", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."score_models" x set
      "name" = v_name,
      "description" = v_description,
      "rules" = v_rules,
      "metrics" = v_metrics,
      "bands" = v_bands,
      "enabled" = v_enabled,
      "version" = x."version" + case when x."rules" = v_rules and x."metrics" = v_metrics and x."bands" = v_bands then 0 else 1 end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."score_model_versions" ("model_id", "version", "tenant_id", "rules", "metrics", "bands", "saved_by")
  values (v_row."id", v_row."version", v_row."tenant_id", v_row."rules", v_row."metrics", v_row."bands", auth.uid())
  on conflict do nothing;
  perform "better_supabase".emit_event('score_model.saved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version"), 'score-models/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/scores');
  perform better_supabase.audit_event(
    event_type => 'score_model.saved',
    category => 'data',
    target_type => 'score_model',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'saved score model',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'key', v_row."key", 'subjectType', v_row."subject_type", 'version', v_row."version")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'key', v_row."key", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'rules', v_row."rules", 'metrics', v_row."metrics", 'bands', v_row."bands", 'enabled', v_row."enabled", 'version', v_row."version", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.score_history (
  tenant       uuid,
  model_key    text,
  subject_type text,
  subject_id   text,
  page_size    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', score_history.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', z.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."computed_at" desc, z."id" desc)
    from (
      select x.*, y."key" as model_key
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = score_history.tenant and y."key" = score_history.model_key
        and x."subject_type" = score_history.subject_type and x."subject_id" = score_history.subject_id
      order by x."computed_at" desc, x."id" desc
      limit least(greatest(coalesce(score_history.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_scores (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', subject_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'modelId', x."model_id", 'modelKey', y."key", 'modelVersion', x."model_version", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'score', x."score", 'band', x."band", 'breakdown', x."breakdown", 'current', x."is_current", 'computedAt', x."computed_at") || jsonb_build_object('modelName', y."name") order by y."key")
    from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
    where x."tenant_id" = subject_scores.tenant and x."subject_type" = subject_scores.subject_type
      and x."subject_id" = subject_scores.subject_id and x."is_current"
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.top_scores (
  tenant    uuid,
  model_key text,
  band      text    DEFAULT NULL::text,
  min_score numeric DEFAULT NULL::numeric,
  page_size integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', top_scores.tenant, 'scores.read'), false)) then
    raise exception 'not allowed to read scores' using errcode = '42501', hint = 'SCORES_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'modelId', z."model_id", 'modelKey', top_scores.model_key, 'modelVersion', z."model_version", 'subjectType', z."subject_type", 'subjectId', z."subject_id", 'score', z."score", 'band', z."band", 'breakdown', z."breakdown", 'current', z."is_current", 'computedAt', z."computed_at") order by z."score" desc, z."computed_at" desc)
    from (
      select x.*
      from "better_supabase"."scores" x join "better_supabase"."score_models" y on y."id" = x."model_id"
      where x."tenant_id" = top_scores.tenant and y."key" = top_scores.model_key and x."is_current"
        and (top_scores.band is null or x."band" = top_scores.band)
        and (top_scores.min_score is null or x."score" >= top_scores.min_score)
      order by x."score" desc, x."computed_at" desc
      limit least(greatest(coalesce(top_scores.page_size, 50), 1), 200)
    ) z
  ), '[]'::jsonb);
end;
$function$;

ALTER TABLE "better_supabase"."score_model_versions"
  ADD CONSTRAINT "score_model_versions_model_id_fkey" FOREIGN KEY (model_id) REFERENCES better_supabase.score_models(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."scores"
  ADD CONSTRAINT "scores_model_id_fkey" FOREIGN KEY (model_id) REFERENCES better_supabase.score_models(id) ON DELETE CASCADE;

CREATE INDEX score_models_subject_idx ON better_supabase.score_models USING btree (tenant_id, subject_type);

CREATE UNIQUE INDEX scores_current_idx ON better_supabase.scores USING btree (model_id, subject_type, subject_id)
  WHERE is_current;

CREATE INDEX scores_history_idx ON better_supabase.scores USING btree (model_id, subject_type, subject_id, computed_at DESC);

CREATE INDEX scores_rank_idx ON better_supabase.scores USING btree (tenant_id, model_id, score DESC)
  WHERE is_current;

CREATE INDEX scores_subject_idx ON better_supabase.scores USING btree (tenant_id, subject_type, subject_id)
  WHERE is_current;

CREATE POLICY "score_model_versions_read" ON "better_supabase"."score_model_versions"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('scores.read'::text) AS tenant_ids_with)));

CREATE POLICY "score_models_read" ON "better_supabase"."score_models"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('scores.read'::text) AS tenant_ids_with)));

CREATE POLICY "scores_read" ON "better_supabase"."scores"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('scores.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."compute_score"(uuid, text, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."compute_score"(uuid, text, text, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_score_models"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_score_models"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_score_model"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_score_model"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."score_history"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."score_history"(uuid, text, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."subject_scores"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."subject_scores"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."top_scores"(uuid, text, text, numeric, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."top_scores"(uuid, text, text, numeric, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."compute_score"(uuid, text, text, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_score_model"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_score_model"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_score_models"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_score_models"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_score_model"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_score_model"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."score_history"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."score_history"(uuid, text, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."subject_scores"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."subject_scores"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."top_scores"(uuid, text, text, numeric, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."top_scores"(uuid, text, text, numeric, integer) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."score_model_versions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."score_model_versions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."score_models" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."score_models" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."scores" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."scores" TO "service_role";
