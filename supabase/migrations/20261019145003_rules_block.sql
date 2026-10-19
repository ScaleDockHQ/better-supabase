SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."rule_evaluations" (
  "id"              bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "rule_id"         uuid                     NOT NULL,
  "version"         integer                  NOT NULL,
  "subject_type"    text                     NOT NULL,
  "subject_id"      text,
  "trigger"         text                     NOT NULL,
  "matched"         boolean                  NOT NULL,
  "results"         jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "mode"            text                     NOT NULL DEFAULT 'live'::text,
  "evaluated_by"    uuid,
  "evaluated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "rule_evaluations_mode_check" CHECK ((mode = ANY (ARRAY['live'::text, 'test'::text]))),
  CONSTRAINT "rule_evaluations_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."rule_evaluations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."rule_fields" (
  "subject_type" text                     NOT NULL,
  "field_id"     text                     NOT NULL,
  "label"        text                     NOT NULL,
  "description"  text,
  "type"         text                     NOT NULL,
  "path"         text                     NOT NULL,
  "column_type"  text                     NOT NULL,
  "nullable"     boolean                  NOT NULL DEFAULT true,
  "options"      jsonb,
  "operators"    jsonb,
  "position"     integer                  NOT NULL DEFAULT 0,
  "updated_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "rule_fields_check" CHECK (((type <> 'date'::text) OR (column_type = ANY (ARRAY['date'::text, 'timestamp'::text, 'timestamptz'::text])))),
  CONSTRAINT "rule_fields_field_id_check" CHECK (((length(field_id) <= 128) AND (field_id ~ '^[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)*$'::text))),
  CONSTRAINT "rule_fields_path_check" CHECK ((path ~ '^[A-Za-z_][A-Za-z0-9_]*([.][A-Za-z_][A-Za-z0-9_]*)*$'::text)),
  CONSTRAINT "rule_fields_pkey" PRIMARY KEY (subject_type, field_id),
  CONSTRAINT "rule_fields_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "rule_fields_type_check"
    CHECK ((type = ANY (ARRAY['text'::text, 'number'::text, 'date'::text, 'select'::text, 'relation'::text, 'multiselect'::text, 'boolean'::text])))
);

ALTER TABLE "better_supabase"."rule_fields"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."rule_versions" (
  "rule_id"         uuid                     NOT NULL,
  "version"         integer                  NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "name"            text                     NOT NULL,
  "conditions"      jsonb                    NOT NULL,
  "actions"         jsonb                    NOT NULL,
  "saved_by"        uuid,
  "saved_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "rule_versions_pkey" PRIMARY KEY (rule_id, VERSION)
);

ALTER TABLE "better_supabase"."rule_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."rules" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "subject_type"    text                     NOT NULL,
  "trigger"         text                     NOT NULL,
  "name"            text                     NOT NULL,
  "description"     text,
  "conditions"      jsonb                    NOT NULL,
  "actions"         jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "enabled"         boolean                  NOT NULL DEFAULT false,
  "stop_processing" boolean                  NOT NULL DEFAULT false,
  "rank"            text                     COLLATE pg_catalog."C" NOT NULL DEFAULT 'V'::text,
  "version"         integer                  NOT NULL DEFAULT 1,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "rules_actions_check" CHECK ((jsonb_typeof(actions) = 'array'::text)),
  CONSTRAINT "rules_description_check" CHECK ((length(description) <= 2000)),
  CONSTRAINT "rules_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "rules_pkey" PRIMARY KEY (id),
  CONSTRAINT "rules_subject_type_check" CHECK ((subject_type ~ '^[a-z][a-z0-9_]{0,62}$'::text)),
  CONSTRAINT "rules_trigger_check" CHECK (((length(trigger) <= 128) AND (trigger ~ '^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$'::text))),
  "created_by"      uuid                     DEFAULT auth.uid(),
  "updated_by"      uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."rules"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.matching_rules (
  tenant       uuid,
  subject_type text,
  trigger      text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."matching_rules"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.rank_rule (
  id   uuid,
  rank text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rank_rule"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_rule_evaluation (
  rule       uuid,
  subject_id text,
  matched    boolean,
  results    jsonb   DEFAULT '{}'::jsonb,
  mode       text    DEFAULT 'live'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_rule_evaluation"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.remove_rule (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_rule"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_boolean (
  value jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_boolean"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_bounds (
  kind      text,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS timestamp WITHOUT time zone[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_bounds"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.rule_check (
  node   jsonb,
  fields jsonb,
  depth  integer DEFAULT 1
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_check"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.rule_date (
  kind      text,
  operator  text,
  operand   jsonb,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_date"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.rule_equal (
  type    text,
  operand jsonb,
  value   jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_equal"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.rule_evaluate (
  conditions jsonb,
  subject    jsonb,
  fields     jsonb,
  time_zone  text                     DEFAULT 'UTC'::text,
  now        timestamp with time zone DEFAULT now()
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_evaluate"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.rule_evaluations_list (
  rule      uuid,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_evaluations_list"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.rule_field_map (
  subject_type text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_field_map"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_fields_list (
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_fields_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_get (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_list (
  value jsonb
)
  RETURNS text[]
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_matches (
  conditions jsonb,
  subject    jsonb,
  fields     jsonb,
  time_zone  text                     DEFAULT 'UTC'::text,
  now        timestamp with time zone DEFAULT now()
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_matches"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.rule_moment (
  kind  text,
  value jsonb
)
  RETURNS timestamp WITHOUT time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_moment"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.rule_node (
  node      jsonb,
  subject   jsonb,
  fields    jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_node"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.rule_numeric (
  value jsonb
)
  RETURNS numeric
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_numeric"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_positive (
  type      text,
  kind      text,
  operator  text,
  operand   jsonb,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_positive"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.rule_text (
  value jsonb
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_text"($1) $function$;

CREATE OR REPLACE FUNCTION api.rule_versions_list (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rule_versions_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.rules_list (
  tenant       uuid,
  subject_type text    DEFAULT NULL::text,
  trigger      text    DEFAULT NULL::text,
  enabled      boolean DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rules_list"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.run_rules (
  tenant       uuid,
  subject_type text,
  trigger      text,
  subject_id   text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."run_rules"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.save_rule (
  tenant uuid,
  rule   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_rule"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_rule_enabled (
  id      uuid,
  enabled boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_rule_enabled"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.sync_rule_fields (
  subject_type text,
  fields       jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."sync_rule_fields"($1, $2) $function$;

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
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'organization_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'organization_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.rule_evaluations', '"better_supabase"."rule_evaluations"', 'organization_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.matching_rules (
  tenant       uuid,
  subject_type text,
  trigger      text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_fields jsonb;
  v_rule "better_supabase"."rules";
  v_result jsonb;
  v_matches jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', matching_rules.tenant, 'rules.read'), false)) then
    raise exception 'You may not read this organization''s rules' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  v_fields := "better_supabase"."rule_field_map"(matching_rules.subject_type);
  for v_rule in
    select * from "better_supabase"."rules" x
    where x."organization_id" = matching_rules.tenant and x."subject_type" = matching_rules.subject_type
      and x."trigger" = matching_rules.trigger and x."enabled"
    order by x."rank" collate "C"
  loop
    v_result := "better_supabase"."rule_evaluate"(v_rule."conditions", matching_rules.subject, v_fields, coalesce(matching_rules.time_zone, 'UTC'), now());
    if (v_result ->> 'matched')::boolean then
      v_matches := v_matches || jsonb_build_array(jsonb_build_object('rule', jsonb_build_object('id', v_rule."id", 'organizationId', v_rule."organization_id", 'subjectType', v_rule."subject_type", 'trigger', v_rule."trigger", 'name', v_rule."name", 'description', v_rule."description", 'conditions', v_rule."conditions", 'actions', v_rule."actions", 'enabled', v_rule."enabled", 'stopProcessing', v_rule."stop_processing", 'rank', v_rule."rank", 'version', v_rule."version", 'createdBy', v_rule."created_by", 'updatedBy', v_rule."updated_by", 'createdAt', v_rule."created_at", 'updatedAt', v_rule."updated_at"), 'results', v_result -> 'results'));
      exit when v_rule."stop_processing";
    end if;
  end loop;
  return v_matches;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rank_rule (
  id   uuid,
  rank text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rules" x where x."id" = rank_rule.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.read'), false)) then
    raise exception 'No rule you can read has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when v_row."enabled" then coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.publish'), false) else coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.edit'), false) end)) then
    raise exception 'You need % to move this rule', case when v_row."enabled" then '''rules.publish''' else '''rules.edit''' end using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if rank_rule.rank is null or rank_rule.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'rank must be a key from rankBetween' using errcode = '22023', hint = 'RULE_RANK_INVALID';
  end if;
  update "better_supabase"."rules" x set "rank" = rank_rule.rank, "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_rule_evaluation (
  rule       uuid,
  subject_id text,
  matched    boolean,
  results    jsonb   DEFAULT '{}'::jsonb,
  mode       text    DEFAULT 'live'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rule "better_supabase"."rules";
  v_row "better_supabase"."rule_evaluations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_rule from "better_supabase"."rules" x where x."id" = record_rule_evaluation.rule;
  if v_rule."id" is null then
    raise exception 'No rule has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') not in ('live', 'test') then
    raise exception 'mode is live or test' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if coalesce(record_rule_evaluation.mode, 'live') = 'live' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role records live evaluations' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_rule."organization_id", 'rules.edit'), false)) then
    raise exception 'Testing rules needs the edit permission' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  insert into "better_supabase"."rule_evaluations" ("organization_id", "rule_id", "version", "subject_type", "subject_id", "trigger", "matched", "results", "mode", "evaluated_by")
  values (v_rule."organization_id", v_rule."id", v_rule."version", v_rule."subject_type", record_rule_evaluation.subject_id, v_rule."trigger",
    coalesce(record_rule_evaluation.matched, false), coalesce(record_rule_evaluation.results, '{}'::jsonb), coalesce(record_rule_evaluation.mode, 'live'), auth.uid())
  returning * into v_row;
  if v_row."mode" = 'live' and v_row."matched" then
    null;
  end if;
  return jsonb_build_object('id', v_row."id"::text, 'organizationId', v_row."organization_id", 'ruleId', v_row."rule_id", 'version', v_row."version", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'trigger', v_row."trigger", 'matched', v_row."matched", 'results', v_row."results", 'mode', v_row."mode", 'evaluatedBy', v_row."evaluated_by", 'evaluatedAt', v_row."evaluated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_rule (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rules" x where x."id" = remove_rule.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."rules" x where x."id" = v_row."id";
  perform better_supabase.audit_event(
    event_type => 'rule.removed',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_boolean (
  value jsonb
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case
    when jsonb_typeof(value) = 'boolean' then (value #>> '{}')::boolean
    when value = '"true"'::jsonb then true
    when value = '"false"'::jsonb then false
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_bounds (
  kind      text,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS timestamp WITHOUT time zone[]
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_day date;
  v_offset integer;
  v_time time;
  v_from timestamp;
  v_to timestamp;
begin
  if jsonb_typeof(value -> 'relative') = 'object' then
    v_day := (rule_bounds.now at time zone rule_bounds.time_zone)::date;
    v_offset := coalesce((value -> 'relative' ->> 'offset')::integer, 0);
    v_day := (v_day + case value -> 'relative' ->> 'unit'
      when 'day' then make_interval(days => v_offset)
      when 'week' then make_interval(weeks => v_offset)
      when 'month' then make_interval(months => v_offset)
      else make_interval(years => v_offset)
    end)::date;
  else
    v_day := (value ->> 'date')::date;
  end if;
  if kind = 'date' then
    return array[v_day::timestamp, (v_day + 1)::timestamp];
  end if;
  v_time := (value ->> 'time')::time;
  v_from := v_day + coalesce(v_time, time '00:00');
  v_to := case when v_time is null then v_from + interval '1 day' else v_from + interval '1 minute' end;
  if kind = 'timestamp' then
    return array[v_from, v_to];
  end if;
  return array[
    (v_from at time zone rule_bounds.time_zone) at time zone 'UTC',
    (v_to at time zone rule_bounds.time_zone) at time zone 'UTC'
  ];
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_check (
  node   jsonb,
  fields jsonb,
  depth  integer DEFAULT 1
)
  RETURNS integer
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_operators constant jsonb := '{"text":{"contains":"one","not_contains":"one","starts_with":"one","ends_with":"one","is":"one","is_not":"one","empty":"none","not_empty":"none"},"number":{"eq":"one","neq":"one","gt":"one","gte":"one","lt":"one","lte":"one","between":"range","not_between":"range","empty":"none","not_empty":"none"},"date":{"is":"one","is_not":"one","is_before":"one","is_after":"one","is_on_or_before":"one","is_on_or_after":"one","between":"range","not_between":"range","empty":"none","not_empty":"none"},"select":{"is":"one","is_not":"one","is_any_of":"many","is_none_of":"many","empty":"none","not_empty":"none"},"relation":{"is":"one","is_not":"one","is_any_of":"many","is_none_of":"many","empty":"none","not_empty":"none"},"multiselect":{"has_any_of":"many","has_all_of":"many","has_none_of":"many","empty":"none","not_empty":"none"},"boolean":{"is":"one","is_not":"one","empty":"none","not_empty":"none"}}'::jsonb;
  v_field jsonb;
  v_path text;
  v_operator text;
  v_arity text;
  v_count integer := 0;
  v_child jsonb;
begin
  if jsonb_typeof(node) is distinct from 'object' or jsonb_typeof(node -> 'id') is distinct from 'string'
    or length(node ->> 'id') not between 1 and 64 then
    raise exception 'Every condition and group needs an id' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if node ->> 'type' = 'rule' then
    if jsonb_typeof(node -> 'path') is distinct from 'array' or jsonb_array_length(node -> 'path') = 0 then
      raise exception 'A condition needs a field path' using errcode = '22023', hint = 'RULE_INVALID';
    end if;
    v_operator := coalesce(node ->> 'operator', '');
    if v_operator = '' then
      return 0;
    end if;
    select string_agg(p.value, '.' order by p.n) into v_path
    from jsonb_array_elements_text(node -> 'path') with ordinality p(value, n);
    v_field := fields -> v_path;
    if v_field is null then
      raise exception 'No rule field %', v_path using errcode = '22023', hint = 'RULE_FIELD_UNKNOWN';
    end if;
    v_arity := v_operators -> (v_field ->> 'type') ->> v_operator;
    if v_arity is null or (jsonb_typeof(v_field -> 'operators') = 'array' and not (v_field -> 'operators') ? v_operator) then
      raise exception 'The field % has no operator %', v_path, v_operator using errcode = '22023', hint = 'RULE_OPERATOR_INVALID';
    end if;
    if (v_arity = 'one' and coalesce(jsonb_typeof(node -> 'value'), 'null') = 'null')
      or (v_arity = 'one' and v_field ->> 'type' = 'date' and jsonb_typeof(node -> 'value') is distinct from 'object')
      or (v_arity = 'many' and (jsonb_typeof(node -> 'value') is distinct from 'array' or jsonb_array_length(node -> 'value') not between 1 and 100))
      or (v_arity = 'range' and (jsonb_typeof(node -> 'value') is distinct from 'array' or jsonb_array_length(node -> 'value') <> 2)) then
      raise exception 'The condition on % has no valid value for %', v_path, v_operator using errcode = '22023', hint = 'RULE_VALUE_INVALID';
    end if;
    if (node -> 'value') is not null and v_arity <> 'none' and length((node -> 'value')::text) > 10000 then
      raise exception 'The value for % is too long', v_path using errcode = '22023', hint = 'RULE_VALUE_INVALID';
    end if;
    return 1;
  end if;
  if node ->> 'type' is distinct from 'group' or coalesce(node ->> 'combinator', '') not in ('and', 'or')
    or jsonb_typeof(node -> 'rules') is distinct from 'array' then
    raise exception 'A group needs a combinator (and, or) and a list of rules' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if depth > 4 then
    raise exception 'Groups nest at most 4 deep' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  for v_child in select x.value from jsonb_array_elements(node -> 'rules') x loop
    v_count := v_count + "better_supabase"."rule_check"(v_child, fields, depth + 1);
  end loop;
  if v_count > 50 then
    raise exception 'A rule holds at most 50 conditions' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_date (
  kind      text,
  operator  text,
  operand   jsonb,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_at timestamp := "better_supabase"."rule_moment"(kind, value);
  v_bounds timestamp[];
begin
  if v_at is null then
    return null;
  end if;
  if operator = 'between' then
    return v_at >= ("better_supabase"."rule_bounds"(kind, operand -> 0, time_zone, now))[1]
      and v_at < ("better_supabase"."rule_bounds"(kind, operand -> 1, time_zone, now))[2];
  end if;
  v_bounds := "better_supabase"."rule_bounds"(kind, operand, time_zone, now);
  case operator
    when 'is' then return v_at >= v_bounds[1] and v_at < v_bounds[2];
    when 'is_before' then return v_at < v_bounds[1];
    when 'is_after' then return v_at >= v_bounds[2];
    when 'is_on_or_before' then return v_at < v_bounds[2];
    when 'is_on_or_after' then return v_at >= v_bounds[1];
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_equal (
  type    text,
  operand jsonb,
  value   jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_boolean boolean;
  v_number numeric;
  v_text text;
begin
  if value is null then
    return null;
  end if;
  if type = 'boolean' then
    v_boolean := "better_supabase"."rule_boolean"(value);
    return case when v_boolean is null then null else v_boolean = coalesce(operand in ('true'::jsonb, '"true"'::jsonb), false) end;
  end if;
  if type = 'number' then
    v_number := "better_supabase"."rule_numeric"(value);
    return case when v_number is null then null else coalesce(v_number = "better_supabase"."rule_numeric"(operand), false) end;
  end if;
  v_text := "better_supabase"."rule_text"(value);
  return case when v_text is null then null else coalesce(v_text = "better_supabase"."rule_text"(operand), false) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_evaluate (
  conditions jsonb,
  subject    jsonb,
  fields     jsonb,
  time_zone  text                     DEFAULT 'UTC'::text,
  now        timestamp with time zone DEFAULT now()
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_node jsonb := "better_supabase"."rule_node"(conditions, subject, fields, time_zone, now);
begin
  return jsonb_build_object(
    'matched', v_node is null or coalesce((v_node ->> 'truth')::boolean, false),
    'results', coalesce(v_node -> 'results', '{}'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_evaluations_list (
  rule      uuid,
  before    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  page_size integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select x."organization_id" into v_tenant from "better_supabase"."rules" x where x."id" = rule_evaluations_list.rule;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'rules.read'), false)) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', y."id"::text, 'organizationId', y."organization_id", 'ruleId', y."rule_id", 'version', y."version", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'trigger', y."trigger", 'matched', y."matched", 'results', y."results", 'mode', y."mode", 'evaluatedBy', y."evaluated_by", 'evaluatedAt', y."evaluated_at") order by y."evaluated_at" desc, y."id" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."rule_evaluations" x
      where x."rule_id" = rule_evaluations_list.rule
        and (rule_evaluations_list.before is null or x."evaluated_at" < rule_evaluations_list.before)
      order by x."evaluated_at" desc, x."id" desc
      limit least(greatest(coalesce(rule_evaluations_list.page_size, 50), 1), 200)
    ) y
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_field_map (
  subject_type text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(x."field_id", jsonb_build_object(
    'type', x."type", 'column', x."path", 'columnType', x."column_type",
    'nullable', x."nullable", 'operators', x."operators"
  )), '{}'::jsonb)
  from "better_supabase"."rule_fields" x where x."subject_type" = rule_field_map.subject_type
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_fields_list (
  subject_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('subjectType', x."subject_type", 'id', x."field_id", 'label', x."label", 'description', x."description", 'type', x."type", 'column', x."path", 'columnType', x."column_type", 'nullable', x."nullable", 'options', x."options", 'operators', x."operators") order by x."subject_type", x."position"), '[]'::jsonb)
  from "better_supabase"."rule_fields" x
  where rule_fields_list.subject_type is null or x."subject_type" = rule_fields_list.subject_type
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_get (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."rules";
begin
  select * into v_row from "better_supabase"."rules" x where x."id" = rule_get.id;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_list (
  value jsonb
)
  RETURNS text[]
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_array jsonb := value;
begin
  if jsonb_typeof(value) = 'string' and left(value #>> '{}', 1) = '[' then
    v_array := (value #>> '{}')::jsonb;
  end if;
  if jsonb_typeof(v_array) is distinct from 'array' then
    return null;
  end if;
  return coalesce((
    select array_agg(case jsonb_typeof(e.value) when 'string' then e.value #>> '{}' else e.value::text end order by e.n)
    from jsonb_array_elements(v_array) with ordinality e(value, n)
  ), '{}');
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_matches (
  conditions jsonb,
  subject    jsonb,
  fields     jsonb,
  time_zone  text                     DEFAULT 'UTC'::text,
  now        timestamp with time zone DEFAULT now()
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select ("better_supabase"."rule_evaluate"(conditions, subject, fields, time_zone, now) ->> 'matched')::boolean
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_moment (
  kind  text,
  value jsonb
)
  RETURNS timestamp WITHOUT time zone
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_text text;
begin
  if jsonb_typeof(value) is distinct from 'string' then
    return null;
  end if;
  v_text := value #>> '{}';
  if kind = 'timestamptz' then
    return v_text::timestamptz at time zone 'UTC';
  end if;
  if kind = 'date' then
    return left(v_text, 10)::date::timestamp;
  end if;
  return v_text::timestamp;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_node (
  node      jsonb,
  subject   jsonb,
  fields    jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_field jsonb;
  v_value jsonb;
  v_operator text := coalesce(node ->> 'operator', '');
  v_base text;
  v_negative boolean;
  v_truth boolean;
  v_part jsonb;
  v_parts boolean[] := '{}';
  v_results jsonb := '{}'::jsonb;
begin
  if node ->> 'type' = 'rule' then
    v_field := fields -> (
      select string_agg(p.value, '.' order by p.n)
      from jsonb_array_elements_text(coalesce(node -> 'path', '[]'::jsonb)) with ordinality p(value, n)
    );
    if v_operator = '' or v_field is null then
      return null;
    end if;
    v_value := subject #> string_to_array(v_field ->> 'column', '.');
    if jsonb_typeof(v_value) = 'null' then
      v_value := null;
    end if;
    v_base := case v_operator when 'not_empty' then 'empty' when 'not_contains' then 'contains' when 'is_not' then 'is' when 'neq' then 'eq' when 'not_between' then 'between' when 'is_none_of' then 'is_any_of' when 'has_none_of' then 'has_any_of' end;
    v_negative := (v_base is not null) <> coalesce((node ->> 'negated')::boolean, false);
    v_operator := coalesce(v_base, v_operator);
    v_truth := "better_supabase"."rule_positive"(v_field ->> 'type', coalesce(v_field ->> 'columnType', 'text'), v_operator, node -> 'value', v_value, time_zone, now);
    if v_negative then
      -- "is not x" also matches records without a value, except for "is not empty".
      if coalesce((v_field ->> 'nullable')::boolean, true) and v_operator <> 'empty' and v_value is null then
        v_truth := true;
      else
        v_truth := not v_truth;
      end if;
    end if;
    return jsonb_build_object('truth', v_truth, 'results', jsonb_build_object(node ->> 'id', v_truth));
  end if;
  for v_part in
    select "better_supabase"."rule_node"(e.value, subject, fields, time_zone, now)
    from jsonb_array_elements(coalesce(node -> 'rules', '[]'::jsonb)) with ordinality e(value, n)
    order by e.n
  loop
    if v_part is not null then
      v_parts := v_parts || (v_part ->> 'truth')::boolean;
      v_results := v_results || (v_part -> 'results');
    end if;
  end loop;
  if cardinality(v_parts) = 0 then
    return null;
  end if;
  if node ->> 'combinator' = 'and' then
    v_truth := not (false = any (v_parts));
  else
    v_truth := true = any (v_parts);
  end if;
  return jsonb_build_object('truth', v_truth, 'results', v_results || jsonb_build_object(node ->> 'id', v_truth));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_numeric (
  value jsonb
)
  RETURNS numeric
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_text text;
begin
  if jsonb_typeof(value) = 'number' then
    return (value #>> '{}')::numeric;
  end if;
  if jsonb_typeof(value) is distinct from 'string' then
    return null;
  end if;
  v_text := trim(value #>> '{}');
  if v_text = '' or lower(v_text) in ('nan', 'infinity', '+infinity', '-infinity', 'inf', '+inf', '-inf') then
    return null;
  end if;
  return v_text::numeric;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_positive (
  type      text,
  kind      text,
  operator  text,
  operand   jsonb,
  value     jsonb,
  time_zone text,
  now       timestamp with time zone
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_text text := "better_supabase"."rule_text"(value);
  v_needle text;
  v_value numeric;
  v_low numeric;
  v_high numeric;
  v_list text[];
begin
  case operator
    when 'empty' then
      return value is null or (type = 'text' and value = '""'::jsonb);
    when 'contains', 'starts_with', 'ends_with' then
      if v_text is null then
        return null;
      end if;
      v_needle := lower(coalesce(operand #>> '{}', ''));
      return case operator
        when 'contains' then strpos(lower(v_text), v_needle) > 0
        when 'starts_with' then left(lower(v_text), length(v_needle)) = v_needle
        else right(lower(v_text), length(v_needle)) = v_needle
      end;
    when 'eq' then
      return "better_supabase"."rule_equal"(type, operand, value);
    when 'gt', 'gte', 'lt', 'lte' then
      v_value := "better_supabase"."rule_numeric"(value);
      v_low := "better_supabase"."rule_numeric"(operand);
      if v_value is null or v_low is null then
        return null;
      end if;
      return case operator
        when 'gt' then v_value > v_low
        when 'gte' then v_value >= v_low
        when 'lt' then v_value < v_low
        else v_value <= v_low
      end;
    when 'is_any_of' then
      if value is null then
        return null;
      end if;
      return v_text is not null and jsonb_typeof(operand) = 'array'
        and exists (select 1 from jsonb_array_elements(operand) e where "better_supabase"."rule_text"(e.value) = v_text);
    when 'has_any_of', 'has_all_of' then
      v_list := "better_supabase"."rule_list"(value);
      if v_list is null or jsonb_typeof(operand) is distinct from 'array' then
        return null;
      end if;
      if operator = 'has_any_of' then
        return exists (select 1 from unnest("better_supabase"."rule_list"(operand)) w where w = any (v_list));
      end if;
      return not exists (select 1 from unnest("better_supabase"."rule_list"(operand)) w where not (w = any (v_list)));
    when 'is' then
      if type = 'date' then
        return "better_supabase"."rule_date"(kind, operator, operand, value, time_zone, now);
      end if;
      return "better_supabase"."rule_equal"(type, operand, value);
    when 'between' then
      if type = 'date' then
        return "better_supabase"."rule_date"(kind, operator, operand, value, time_zone, now);
      end if;
      v_value := "better_supabase"."rule_numeric"(value);
      v_low := least("better_supabase"."rule_numeric"(operand -> 0), "better_supabase"."rule_numeric"(operand -> 1));
      v_high := greatest("better_supabase"."rule_numeric"(operand -> 0), "better_supabase"."rule_numeric"(operand -> 1));
      if v_value is null or v_low is null or v_high is null then
        return null;
      end if;
      return v_value >= v_low and v_value <= v_high;
    else
      return "better_supabase"."rule_date"(kind, operator, operand, value, time_zone, now);
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_text (
  value jsonb
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case jsonb_typeof(value)
    when 'string' then value #>> '{}'
    when 'number' then value::text
    when 'boolean' then value::text
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rule_versions_list (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select x."organization_id" into v_tenant from "better_supabase"."rules" x where x."id" = rule_versions_list.id;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'rules.read'), false)) then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'ruleId', x."rule_id", 'version', x."version", 'name', x."name",
      'conditions', x."conditions", 'actions', x."actions",
      'savedBy', x."saved_by", 'savedAt', x."saved_at"
    ) order by x."version" desc), '[]'::jsonb)
    from "better_supabase"."rule_versions" x where x."rule_id" = rule_versions_list.id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rules_list (
  tenant       uuid,
  subject_type text    DEFAULT NULL::text,
  trigger      text    DEFAULT NULL::text,
  enabled      boolean DEFAULT NULL::boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', rules_list.tenant, 'rules.read'), false)) then
    raise exception 'You may not read this organization''s rules' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."organization_id", 'subjectType', x."subject_type", 'trigger', x."trigger", 'name', x."name", 'description', x."description", 'conditions', x."conditions", 'actions', x."actions", 'enabled', x."enabled", 'stopProcessing', x."stop_processing", 'rank', x."rank", 'version', x."version", 'createdBy', x."created_by", 'updatedBy', x."updated_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."subject_type", x."trigger", x."rank" collate "C"), '[]'::jsonb)
    from "better_supabase"."rules" x
    where x."organization_id" = rules_list.tenant
      and (rules_list.subject_type is null or x."subject_type" = rules_list.subject_type)
      and (rules_list.trigger is null or x."trigger" = rules_list.trigger)
      and (rules_list.enabled is null or x."enabled" = rules_list.enabled)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.run_rules (
  tenant       uuid,
  subject_type text,
  trigger      text,
  subject_id   text,
  subject      jsonb,
  time_zone    text  DEFAULT 'UTC'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_fields jsonb;
  v_rule "better_supabase"."rules";
  v_result jsonb;
  v_matches jsonb := '[]'::jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role runs rules' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  v_fields := "better_supabase"."rule_field_map"(run_rules.subject_type);
  for v_rule in
    select * from "better_supabase"."rules" x
    where x."organization_id" = run_rules.tenant and x."subject_type" = run_rules.subject_type
      and x."trigger" = run_rules.trigger and x."enabled"
    order by x."rank" collate "C"
  loop
    v_result := "better_supabase"."rule_evaluate"(v_rule."conditions", run_rules.subject, v_fields, coalesce(run_rules.time_zone, 'UTC'), now());
    perform "better_supabase"."record_rule_evaluation"(v_rule."id", run_rules.subject_id, (v_result ->> 'matched')::boolean, v_result -> 'results', 'live');
    if (v_result ->> 'matched')::boolean then
      v_matches := v_matches || jsonb_build_array(jsonb_build_object('rule', jsonb_build_object('id', v_rule."id", 'organizationId', v_rule."organization_id", 'subjectType', v_rule."subject_type", 'trigger', v_rule."trigger", 'name', v_rule."name", 'description', v_rule."description", 'conditions', v_rule."conditions", 'actions', v_rule."actions", 'enabled', v_rule."enabled", 'stopProcessing', v_rule."stop_processing", 'rank', v_rule."rank", 'version', v_rule."version", 'createdBy', v_rule."created_by", 'updatedBy', v_rule."updated_by", 'createdAt', v_rule."created_at", 'updatedAt', v_rule."updated_at"), 'results', v_result -> 'results'));
      exit when v_rule."stop_processing";
    end if;
  end loop;
  return v_matches;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_rule (
  tenant uuid,
  rule   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old "better_supabase"."rules";
  v_row "better_supabase"."rules";
  v_subject_type text;
  v_trigger text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_actions jsonb;
  v_enabled boolean;
  v_stop boolean;
  v_fields jsonb;
  v_action jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(rule) is distinct from 'object' then
    raise exception 'rule must be an object' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  v_id := nullif(rule ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."rules" x where x."id" = v_id and x."organization_id" = save_rule.tenant for update;
    if v_old."id" is null then
      raise exception 'No rule in this organization has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
    end if;
    if rule ? 'version' and (rule ->> 'version')::integer is distinct from v_old."version" then
      raise exception 'The rule changed since it was read' using errcode = '40001', hint = 'RULE_CONFLICT';
    end if;
    if rule ? 'subjectType' and rule ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A rule''s subject type can''t change' using errcode = '22023', hint = 'RULE_INVALID';
    end if;
  end if;
  v_subject_type := coalesce(v_old."subject_type", rule ->> 'subjectType');
  v_trigger := coalesce(rule ->> 'trigger', v_old."trigger");
  v_name := coalesce(nullif(trim(rule ->> 'name'), ''), v_old."name");
  v_description := case when rule ? 'description' then nullif(trim(rule ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(rule -> 'conditions', v_old."conditions", '{"id": "root", "type": "group", "combinator": "and", "rules": []}'::jsonb);
  v_actions := coalesce(rule -> 'actions', v_old."actions", '[]'::jsonb);
  v_enabled := coalesce((rule ->> 'enabled')::boolean, v_old."enabled", false);
  v_stop := coalesce((rule ->> 'stopProcessing')::boolean, v_old."stop_processing", false);
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when (v_enabled or coalesce(v_old."enabled", false)) then coalesce(better_supabase.can('tenant', save_rule.tenant, 'rules.publish'), false) else coalesce(better_supabase.can('tenant', save_rule.tenant, 'rules.edit'), false) end)) then
    raise exception 'You need % to save this rule', case when (v_enabled or coalesce(v_old."enabled", false)) then '''rules.publish''' else '''rules.edit''' end using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'A rule needs a subject type' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if v_trigger is null or length(v_trigger) > 128 or v_trigger !~ '^[a-z][a-z0-9_]*([.:][a-z0-9_]+)*$' then
    raise exception 'A rule needs a trigger such as expense.submitted' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  if v_name is null or length(v_name) > 200 then
    raise exception 'A rule needs a name of at most 200 characters' using errcode = '22023', hint = 'RULE_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_subject_type);
  if v_fields = '{}'::jsonb then
    raise exception 'No rule fields for %; sync them first', v_subject_type using errcode = '22023', hint = 'RULE_SUBJECT_UNKNOWN';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if jsonb_typeof(v_actions) is distinct from 'array' or jsonb_array_length(v_actions) > 20 then
    raise exception 'actions must be an array of at most 20 entries' using errcode = '22023', hint = 'RULE_ACTIONS_INVALID';
  end if;
  for v_action in select x.value from jsonb_array_elements(v_actions) x loop
    if jsonb_typeof(v_action) is distinct from 'object' or v_action ->> 'kind' is null
      or length(v_action ->> 'kind') > 128 or v_action ->> 'kind' !~ '^[a-z][a-z0-9_]*([.][a-z0-9_]+)*$'
      or (v_action ? 'config' and jsonb_typeof(v_action -> 'config') is distinct from 'object') then
      raise exception 'Every action needs a kind such as approvals.request and an optional config object' using errcode = '22023', hint = 'RULE_ACTIONS_INVALID';
    end if;
  end loop;
  if v_old."id" is null then
    insert into "better_supabase"."rules" ("organization_id", "subject_type", "trigger", "name", "description", "conditions", "actions", "enabled", "stop_processing", "rank")
    values (save_rule.tenant, v_subject_type, v_trigger, v_name, v_description, v_conditions, v_actions, v_enabled, v_stop,
      case
    when (select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) is null then 'V'
    when length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) = length((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type)) then (select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) || 'V'
    else left((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type), length(substring((select max(x."rank" collate "C") from "better_supabase"."rules" x where x."organization_id" = save_rule.tenant and x."subject_type" = v_subject_type) from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
    returning * into v_row;
  elsif v_old."trigger" = v_trigger and v_old."name" = v_name
    and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions and v_old."actions" = v_actions
    and v_old."enabled" = v_enabled and v_old."stop_processing" = v_stop then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."organization_id", 'subjectType', v_old."subject_type", 'trigger', v_old."trigger", 'name', v_old."name", 'description', v_old."description", 'conditions', v_old."conditions", 'actions', v_old."actions", 'enabled', v_old."enabled", 'stopProcessing', v_old."stop_processing", 'rank', v_old."rank", 'version', v_old."version", 'createdBy', v_old."created_by", 'updatedBy', v_old."updated_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."rules" x set
      "trigger" = v_trigger,
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "actions" = v_actions,
      "enabled" = v_enabled,
      "stop_processing" = v_stop,
      "version" = x."version" + 1,
      "updated_by" = auth.uid(),
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."rule_versions" ("rule_id", "version", "organization_id", "name", "conditions", "actions", "saved_by")
  values (v_row."id", v_row."version", v_row."organization_id", v_row."name", v_row."conditions", v_row."actions", auth.uid())
  on conflict do nothing;
  perform better_supabase.audit_event(
    event_type => 'rule.saved',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  if v_row."enabled" and not coalesce(v_old."enabled", false) then
    perform better_supabase.audit_event(
    event_type => 'rule.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  elsif not v_row."enabled" and coalesce(v_old."enabled", false) then
    perform better_supabase.audit_event(
    event_type => 'rule.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_rule_enabled (
  id      uuid,
  enabled boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rules" x where x."id" = set_rule_enabled.id for update;
  if v_row."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.read'), false)) then
    raise exception 'No rule you can read has this id' using errcode = 'P0002', hint = 'RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'rules.publish'), false)) then
    raise exception 'Publishing rules needs the publish permission' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if v_row."enabled" = coalesce(set_rule_enabled.enabled, false) then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."rules" x set "enabled" = coalesce(set_rule_enabled.enabled, false), "updated_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  if v_row."enabled" then
    perform better_supabase.audit_event(
    event_type => 'rule.enabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  else
    perform better_supabase.audit_event(
    event_type => 'rule.disabled',
    category => 'configuration',
    target_type => 'rule',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."organization_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."organization_id"::text, 'ruleId', v_row."id"::text, 'name', v_row."name", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'version', v_row."version"),
    actor_id => auth.uid()
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."organization_id", 'subjectType', v_row."subject_type", 'trigger', v_row."trigger", 'name', v_row."name", 'description', v_row."description", 'conditions', v_row."conditions", 'actions', v_row."actions", 'enabled', v_row."enabled", 'stopProcessing', v_row."stop_processing", 'rank', v_row."rank", 'version', v_row."version", 'createdBy', v_row."created_by", 'updatedBy', v_row."updated_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_rule_fields (
  subject_type text,
  fields       jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_count integer;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'Only the service role syncs rule fields' using errcode = '42501', hint = 'RULE_FORBIDDEN';
  end if;
  if jsonb_typeof(fields) is distinct from 'array' then
    raise exception 'fields must be an array' using errcode = '22023', hint = 'RULE_FIELDS_INVALID';
  end if;
  insert into "better_supabase"."rule_fields" ("subject_type", "field_id", "label", "description", "type", "path", "column_type", "nullable", "options", "operators", "position")
  select sync_rule_fields.subject_type, x.value ->> 'id', coalesce(x.value ->> 'label', x.value ->> 'id'), x.value ->> 'description',
    x.value ->> 'type', coalesce(x.value ->> 'column', x.value ->> 'id'), coalesce(x.value ->> 'columnType', 'text'),
    coalesce((x.value ->> 'nullable')::boolean, true), x.value -> 'options', x.value -> 'operators', x.n::integer
  from jsonb_array_elements(fields) with ordinality x(value, n)
  on conflict ("subject_type", "field_id") do update set
    "label" = excluded."label",
    "description" = excluded."description",
    "type" = excluded."type",
    "path" = excluded."path",
    "column_type" = excluded."column_type",
    "nullable" = excluded."nullable",
    "options" = excluded."options",
    "operators" = excluded."operators",
    "position" = excluded."position",
    "updated_at" = now();
  delete from "better_supabase"."rule_fields" x
  where x."subject_type" = sync_rule_fields.subject_type
    and not exists (select 1 from jsonb_array_elements(fields) y where y.value ->> 'id' = x."field_id");
  select count(*) into v_count from "better_supabase"."rule_fields" x where x."subject_type" = sync_rule_fields.subject_type;
  return v_count;
exception when check_violation or not_null_violation then
  raise exception 'A rule field has an invalid id, type, column or column type' using errcode = '22023', hint = 'RULE_FIELDS_INVALID';
end;
$function$;

ALTER TABLE "better_supabase"."rule_evaluations"
  ADD CONSTRAINT "rule_evaluations_rule_id_fkey" FOREIGN KEY (rule_id) REFERENCES better_supabase.rules(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."rule_versions"
  ADD CONSTRAINT "rule_versions_rule_id_fkey" FOREIGN KEY (rule_id) REFERENCES better_supabase.rules(id) ON DELETE CASCADE;

CREATE INDEX rule_evaluations_rule_idx ON better_supabase.rule_evaluations USING btree (rule_id, evaluated_at DESC);

CREATE INDEX rule_evaluations_tenant_idx ON better_supabase.rule_evaluations USING btree (organization_id, evaluated_at DESC);

CREATE INDEX rule_versions_tenant_idx ON better_supabase.rule_versions USING btree (organization_id);

CREATE INDEX rules_trigger_idx ON better_supabase.rules USING btree (organization_id, subject_type, TRIGGER, rank);

REVOKE ALL ON FUNCTION "api"."matching_rules"(uuid, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."matching_rules"(uuid, text, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rank_rule"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rank_rule"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_rule_evaluation"(uuid, text, boolean, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_rule_evaluation"(uuid, text, boolean, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_boolean"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_boolean"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_bounds"(text, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_bounds"(text, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_check"(jsonb, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_check"(jsonb, jsonb, integer) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_date"(text, text, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_date"(text, text, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_equal"(text, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_equal"(text, jsonb, jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_evaluate"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_evaluate"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_evaluations_list"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_evaluations_list"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_field_map"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_field_map"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_fields_list"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_fields_list"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_list"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_list"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_matches"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_matches"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_moment"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_moment"(text, jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_node"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_node"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_numeric"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_numeric"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_positive"(text, text, text, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_positive"(text, text, text, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_text"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_text"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rule_versions_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rule_versions_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rules_list"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rules_list"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."run_rules"(uuid, text, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."run_rules"(uuid, text, text, text, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_rule"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_rule"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_rule_enabled"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_rule_enabled"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."sync_rule_fields"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sync_rule_fields"(text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."matching_rules"(uuid, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."matching_rules"(uuid, text, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rank_rule"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rank_rule"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_rule_evaluation"(uuid, text, boolean, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_rule_evaluation"(uuid, text, boolean, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_boolean"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_boolean"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_bounds"(text, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_bounds"(text, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_check"(jsonb, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_check"(jsonb, jsonb, integer) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_date"(text, text, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_date"(text, text, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_equal"(text, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_equal"(text, jsonb, jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_evaluate"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_evaluate"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_evaluations_list"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_evaluations_list"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_field_map"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_field_map"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_fields_list"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_fields_list"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_list"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_list"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_matches"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_matches"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_moment"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_moment"(text, jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_node"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_node"(jsonb, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_numeric"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_numeric"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_positive"(text, text, text, jsonb, jsonb, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_positive"(text, text, text, jsonb, jsonb, text, timestamp WITH time zone) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_text"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_text"(jsonb) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rule_versions_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rule_versions_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rules_list"(uuid, text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rules_list"(uuid, text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."run_rules"(uuid, text, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."run_rules"(uuid, text, text, text, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_rule"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_rule"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_rule_enabled"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_rule_enabled"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sync_rule_fields"(text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sync_rule_fields"(text, jsonb) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."rule_evaluations" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."rule_fields" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."rule_versions" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."rules" TO "service_role";

ALTER TABLE "better_supabase"."rules"
  ADD CONSTRAINT "rules_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX rules_created_by_idx ON better_supabase.rules USING btree (created_by)
  WHERE (created_by IS NOT NULL);

ALTER TABLE "better_supabase"."rules"
  ADD CONSTRAINT "rules_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX rules_updated_by_idx ON better_supabase.rules USING btree (updated_by)
  WHERE (updated_by IS NOT NULL);
