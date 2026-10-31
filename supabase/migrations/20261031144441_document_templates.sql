SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."document_templates" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "legal_entity_id" uuid,
  "document_type"   text                     NOT NULL,
  "language"        text,
  "name"            text                     NOT NULL DEFAULT 'default'::text,
  "body"            text                     NOT NULL,
  "version"         integer                  NOT NULL DEFAULT 1,
  "active"          boolean                  NOT NULL DEFAULT true,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "document_templates_body_check" CHECK (((length(btrim(body)) > 0) AND (length(body) <= 200000))),
  CONSTRAINT "document_templates_document_type_check"
    CHECK ((document_type = ANY (ARRAY['invoice'::text, 'credit_note'::text, 'quote'::text, 'order'::text, 'dunning_letter'::text, 'delivery_note'::text, 'statement'::text]))),
  CONSTRAINT "document_templates_language_check" CHECK (((language IS NULL) OR (language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'::text))),
  CONSTRAINT "document_templates_name_check" CHECK ((name ~ '^[a-z][a-z0-9_-]{0,63}$'::text)),
  CONSTRAINT "document_templates_pkey" PRIMARY KEY (id),
  CONSTRAINT "document_templates_version_check" CHECK ((version >= 1)),
  "created_by"      uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."document_templates"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."document_text_blocks" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "legal_entity_id" uuid,
  "key"             text                     NOT NULL,
  "language"        text,
  "body"            text                     NOT NULL,
  "version"         integer                  NOT NULL DEFAULT 1,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "document_text_blocks_body_check" CHECK (((length(btrim(body)) > 0) AND (length(body) <= 200000))),
  CONSTRAINT "document_text_blocks_key_check" CHECK ((key ~ '^[a-z][a-z0-9_]{0,63}$'::text)),
  CONSTRAINT "document_text_blocks_language_check" CHECK (((language IS NULL) OR (language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'::text))),
  CONSTRAINT "document_text_blocks_pkey" PRIMARY KEY (id),
  CONSTRAINT "document_text_blocks_version_check" CHECK ((version >= 1)),
  "created_by"      uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."document_text_blocks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."rendered_documents" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"        uuid                     NOT NULL,
  "document_type"    text                     NOT NULL,
  "document_id"      uuid                     NOT NULL,
  "language"         text,
  "legal_entity_id"  uuid,
  "contract_version" integer                  NOT NULL,
  "template_id"      uuid,
  "template_version" integer,
  "template"         jsonb,
  "blocks"           jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "variables"        jsonb                    NOT NULL,
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "rendered_documents_blocks_check" CHECK ((jsonb_typeof(blocks) = 'object'::text)),
  CONSTRAINT "rendered_documents_document_type_check"
    CHECK ((document_type = ANY (ARRAY['invoice'::text, 'credit_note'::text, 'quote'::text, 'order'::text, 'dunning_letter'::text, 'delivery_note'::text, 'statement'::text]))),
  CONSTRAINT "rendered_documents_pkey" PRIMARY KEY (id),
  CONSTRAINT "rendered_documents_tenant_id_document_type_document_id_key" UNIQUE (tenant_id, document_type, document_id),
  CONSTRAINT "rendered_documents_variables_check" CHECK ((jsonb_typeof(variables) = 'object'::text)),
  "created_by"       uuid                     DEFAULT auth.uid()
);

ALTER TABLE "better_supabase"."rendered_documents"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.document_address (
  address jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_address"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_entity (
  tenant       uuid,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_entity"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_party (
  tenant     uuid,
  company_id text,
  contact_id text,
  buyer      jsonb DEFAULT NULL::jsonb,
  email      text  DEFAULT NULL::text,
  address    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_party"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.document_render_live (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text DEFAULT NULL::text,
  template_name text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_render_live"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.document_slot_rank (
  entity          uuid,
  wanted_entity   uuid,
  language        text,
  wanted_language text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_slot_rank"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.document_tax_summary (
  lines jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_tax_summary"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_template_contract (
  document_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_template_contract"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_template_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_template_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_text_block_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_text_block_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.document_variables (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_delivery_note (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_delivery_note"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_dunning_letter (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_dunning_letter"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_invoice (
  tenant      uuid,
  document_id uuid,
  credit_note boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_invoice"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_order (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_order"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_quote (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_quote"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_variables_statement (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_variables_statement"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.document_visible (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."document_visible"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.freeze_document (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text DEFAULT NULL::text,
  template_name text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."freeze_document"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.get_document_template (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_document_template"($1) $function$;

CREATE OR REPLACE FUNCTION api.import_document_template (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_document_template"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_document_text_block (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_document_text_block"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_document_templates (
  tenant          uuid,
  document_type   text    DEFAULT NULL::text,
  legal_entity_id uuid    DEFAULT NULL::uuid,
  active_only     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_document_templates"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_document_text_blocks (
  tenant          uuid,
  key             text DEFAULT NULL::text,
  legal_entity_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_document_text_blocks"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.render_document (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text    DEFAULT NULL::text,
  fresh         boolean DEFAULT false,
  template_name text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."render_document"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.resolve_document_blocks (
  tenant          uuid,
  keys            text[],
  legal_entity_id uuid   DEFAULT NULL::uuid,
  language        text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_document_blocks"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.resolve_document_template (
  tenant          uuid,
  document_type   text,
  legal_entity_id uuid DEFAULT NULL::uuid,
  language        text DEFAULT NULL::text,
  name            text DEFAULT 'default'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."resolve_document_template"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_document_template (
  tenant          uuid,
  document_type   text,
  body            text,
  language        text    DEFAULT NULL::text,
  name            text    DEFAULT 'default'::text,
  legal_entity_id uuid    DEFAULT NULL::uuid,
  active          boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_document_template"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.save_document_text_block (
  tenant          uuid,
  key             text,
  body            text,
  language        text DEFAULT NULL::text,
  legal_entity_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_document_text_block"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.set_document_template_active (
  template_id uuid,
  active      boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_document_template_active"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.validate_document_template (
  document_type text,
  body          text,
  text_block    boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."validate_document_template"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.assert_document_template (
  document_type text,
  body          text,
  text_block    boolean DEFAULT false
)
  RETURNS void
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_issues jsonb;
  v_code text;
  v_message text;
begin
  v_issues := "better_supabase"."validate_document_template"(assert_document_template.document_type, assert_document_template.body, assert_document_template.text_block);
  if jsonb_array_length(v_issues) = 0 then
    return;
  end if;
  v_code := v_issues -> 0 ->> 'code';
  v_message := v_issues -> 0 ->> 'message';
  if v_code = 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE' then
    raise exception '%', v_message using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE';
  elsif v_code = 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER' then
    raise exception '%', v_message using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER';
  end if;
  raise exception '%', v_message using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_SYNTAX';
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
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_address (
  address jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'line1', nullif(btrim(coalesce(a.j ->> 'line1', a.j ->> 'street', a.j ->> 'address1')), ''),
    'line2', nullif(btrim(coalesce(a.j ->> 'line2', a.j ->> 'address2')), ''),
    'postalCode', nullif(btrim(coalesce(a.j ->> 'postalCode', a.j ->> 'postal_code', a.j ->> 'zip')), ''),
    'city', nullif(btrim(a.j ->> 'city'), ''),
    'region', nullif(btrim(coalesce(a.j ->> 'region', a.j ->> 'state')), ''),
    'country', nullif(btrim(a.j ->> 'country'), '')
  )
  from (select case when jsonb_typeof(document_address.address) = 'object' then document_address.address else '{}'::jsonb end as j) a
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_entity (
  tenant       uuid,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_row "better_supabase"."legal_entities"%rowtype;
begin
  v_id := "better_supabase"."legal_entity_of"(document_entity.tenant, document_entity.legal_entity);
  if v_id is not null then
    select * into v_row from "better_supabase"."legal_entities" x where x."id" = v_id;
  end if;
  if v_row."id" is null then
    return jsonb_build_object('id', null::text, 'code', null::text, 'name', null::text, 'address', '{"line1":null,"line2":null,"postalCode":null,"city":null,"region":null,"country":null}'::jsonb, 'vatNumber', null::text, 'cocNumber', null::text, 'iban', null::text, 'bic', null::text, 'logoAttachmentId', null::text, 'defaultCurrency', null::text);
  end if;
  return jsonb_build_object('id', v_row."id", 'code', v_row."code", 'name', v_row."name", 'address', "better_supabase"."document_address"(v_row."address"), 'vatNumber', v_row."vat_number", 'cocNumber', v_row."coc_number", 'iban', v_row."iban", 'bic', v_row."bic", 'logoAttachmentId', v_row."logo_attachment_id", 'defaultCurrency', v_row."default_currency");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_freeze (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text DEFAULT NULL::text,
  template_name text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."rendered_documents"%rowtype;
  v_live jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('rendered_documents:' || document_freeze.tenant::text || ':' || document_freeze.document_id::text, 0));
  select * into v_row from "better_supabase"."rendered_documents" s
    where s."tenant_id" = document_freeze.tenant
      and s."document_type" = document_freeze.document_type
      and s."document_id" = document_freeze.document_id;
  if found then
    return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
  end if;
  v_live := "better_supabase"."document_render_live"(document_freeze.tenant, document_freeze.document_type, document_freeze.document_id, document_freeze.language, document_freeze.template_name);
  insert into "better_supabase"."rendered_documents" ("tenant_id", "document_type", "document_id", "language", "legal_entity_id", "contract_version", "template_id", "template_version", "template", "blocks", "variables")
  values (
    document_freeze.tenant, document_freeze.document_type, document_freeze.document_id,
    v_live ->> 'language', nullif(v_live ->> 'legalEntityId', '')::uuid, (v_live ->> 'contractVersion')::integer,
    nullif(v_live #>> '{template,id}', '')::uuid, nullif(v_live #>> '{template,version}', '')::integer,
    v_live -> 'template', v_live -> 'blocks', v_live -> 'variables')
  returning * into v_row;
  perform "better_supabase".emit_event('document_snapshot.created', jsonb_build_object('organizationId', v_row."tenant_id", 'snapshotId', v_row."id", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'templateVersion', v_row."template_version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_snapshot.created',
    category => 'data',
    target_type => 'document_snapshot',
    record_id => v_row."id"::text,
    summary => 'froze ' || v_row."document_type" || ' ' || v_row."document_id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'snapshotId', v_row."id", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'templateVersion', v_row."template_version")
  );
  return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_party (
  tenant     uuid,
  company_id text,
  contact_id text,
  buyer      jsonb DEFAULT NULL::jsonb,
  email      text  DEFAULT NULL::text,
  address    jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_company "better_supabase"."companies"%rowtype;
  v_person "better_supabase"."people"%rowtype;
  v_buyer jsonb := case when jsonb_typeof(document_party.buyer) = 'object' then document_party.buyer else '{}'::jsonb end;
  v_company_found boolean := false;
  v_person_found boolean := false;
begin
  select * into v_company from "better_supabase"."companies" x where x."id"::text = document_party.company_id and x."tenant_id" = document_party.tenant;
  v_company_found := found;
  select * into v_person from "better_supabase"."people" x where x."id"::text = coalesce(document_party.contact_id, document_party.company_id) and x."tenant_id" = document_party.tenant;
  v_person_found := found;
  return jsonb_build_object(
    'id', case when v_company_found then document_party.company_id when v_person_found then coalesce(document_party.contact_id, document_party.company_id) else null end,
    'type', case when v_company_found then 'company' when v_person_found then 'person' else null end,
    'name', coalesce(nullif(v_buyer ->> 'name', ''), case when v_company_found then v_company."name"::text end, case when v_person_found then v_person."name"::text end),
    'email', coalesce(nullif(v_buyer ->> 'email', ''), case when v_person_found then v_person."email"::text end, nullif(document_party.email, '')),
    'vatNumber', coalesce(nullif(coalesce(v_buyer ->> 'vatNumber', v_buyer ->> 'vat_number', v_buyer ->> 'vatId'), ''), case when v_company_found then v_company."vat_id"::text end),
    'language', coalesce(nullif(v_buyer ->> 'language', ''), case when v_company_found then v_company."language"::text end, case when v_person_found then v_person."language"::text end),
    'address', "better_supabase"."document_address"(coalesce(case when jsonb_typeof(v_buyer -> 'address') = 'object' then v_buyer -> 'address' end, case when v_company_found then v_company."address" end, document_party.address))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_render_live (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text DEFAULT NULL::text,
  template_name text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_vars jsonb;
  v_entity uuid;
  v_language text;
  v_template jsonb;
  v_keys text[] := '{}'::text[];
  v_text_key text;
  v_blocks jsonb := '{}'::jsonb;
begin
  v_language := lower(nullif(btrim(document_render_live.language), ''));
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a language is a code such as nl or nl-NL' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  v_vars := "better_supabase"."document_variables"(document_render_live.tenant, document_render_live.document_type, document_render_live.document_id);
  v_entity := nullif(v_vars #>> '{entity,id}', '')::uuid;
  v_language := coalesce(v_language, lower(nullif(btrim(v_vars #>> '{buyer,language}'), '')));
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    v_language := null;
  end if;
  v_template := "better_supabase"."resolve_document_template"(document_render_live.tenant, document_render_live.document_type, v_entity, v_language, coalesce(document_render_live.template_name, 'default'));
  if v_template is not null then
    select coalesce(array_agg(distinct m[1]), '{}'::text[]) into v_keys
    from regexp_matches(v_template ->> 'body', 'texts\.([a-z][a-z0-9_]{0,63})', 'g') m;
    v_text_key := nullif(v_vars #>> '{document,textKey}', '');
    if v_text_key is not null and v_text_key ~ '^[a-z][a-z0-9_]{0,63}$' and not v_text_key = any (v_keys) then
      v_keys := v_keys || v_text_key;
    end if;
    v_blocks := "better_supabase"."resolve_document_blocks"(document_render_live.tenant, v_keys, v_entity, v_language);
    if v_text_key is not null and v_blocks ? v_text_key then
      v_blocks := v_blocks || jsonb_build_object('dunning', v_blocks -> v_text_key);
    end if;
  end if;
  v_vars := jsonb_set(v_vars, '{document,language}', coalesce(to_jsonb(v_language), 'null'::jsonb));
  return jsonb_build_object(
    'contractVersion', 1,
    'documentType', document_render_live.document_type,
    'documentId', document_render_live.document_id,
    'legalEntityId', v_entity,
    'language', v_language,
    'variables', v_vars,
    'template', v_template,
    'blocks', v_blocks,
    'frozen', false,
    'frozenAt', null,
    'snapshotId', null
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_slot_rank (
  entity          uuid,
  wanted_entity   uuid,
  language        text,
  wanted_language text
)
  RETURNS integer
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case when document_slot_rank.entity is not distinct from document_slot_rank.wanted_entity and document_slot_rank.entity is not null then 0 else 3 end
    + case
      when document_slot_rank.wanted_language is not null and document_slot_rank.language = document_slot_rank.wanted_language then 0
      when document_slot_rank.wanted_language is not null and document_slot_rank.language = split_part(document_slot_rank.wanted_language, '-', 1) then 1
      when document_slot_rank.language is null then 2
      else 6
    end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_snapshot_immutable()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  raise exception 'a frozen document never changes' using errcode = '23000', hint = 'DOCUMENT_SNAPSHOT_IMMUTABLE';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_tax_summary (
  lines jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'taxRateBps', g.rate,
    'taxCode', g.code,
    'net', g.net::text,
    'tax', round(g.net * g.rate / 10000.0)::bigint::text,
    'gross', (g.net + round(g.net * g.rate / 10000.0)::bigint)::text
  ) order by g.rate, g.code), '[]'::jsonb)
  from (
    select coalesce((l ->> 'taxRateBps')::integer, 0) as rate, l ->> 'taxCode' as code, sum((l ->> 'amount')::bigint) as net
    from jsonb_array_elements(document_tax_summary.lines) l
    group by 1, 2
  ) g
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_template_contract (
  document_type text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
declare
  v_all constant jsonb := '{"invoice":{"version":1,"documentType":"invoice","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"credit_note":{"version":1,"documentType":"credit_note","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"},{"path":"document.originalNumber","type":"string"}]},"quote":{"version":1,"documentType":"quote","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.validUntil","type":"date"},{"path":"document.revision","type":"number"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"order":{"version":1,"documentType":"order","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"shipping","type":"object"},{"path":"shipping.address","type":"object"},{"path":"shipping.address.line1","type":"string"},{"path":"shipping.address.line2","type":"string"},{"path":"shipping.address.postalCode","type":"string"},{"path":"shipping.address.city","type":"string"},{"path":"shipping.address.region","type":"string"},{"path":"shipping.address.country","type":"string"},{"path":"shipping.carrier","type":"string"},{"path":"shipping.trackingNumber","type":"string"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"dunning_letter":{"version":1,"documentType":"dunning_letter","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.dueOn","type":"date"},{"path":"document.level","type":"number"},{"path":"document.textKey","type":"string"},{"path":"document.asOf","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"delivery_note":{"version":1,"documentType":"delivery_note","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"shipping","type":"object"},{"path":"shipping.address","type":"object"},{"path":"shipping.address.line1","type":"string"},{"path":"shipping.address.line2","type":"string"},{"path":"shipping.address.postalCode","type":"string"},{"path":"shipping.address.city","type":"string"},{"path":"shipping.address.region","type":"string"},{"path":"shipping.address.country","type":"string"},{"path":"shipping.carrier","type":"string"},{"path":"shipping.trackingNumber","type":"string"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]},"statement":{"version":1,"documentType":"statement","variables":[{"path":"document","type":"object"},{"path":"document.id","type":"string"},{"path":"document.type","type":"string"},{"path":"document.number","type":"string"},{"path":"document.title","type":"string"},{"path":"document.status","type":"string"},{"path":"document.date","type":"date"},{"path":"document.currency","type":"string"},{"path":"document.language","type":"string"},{"path":"document.note","type":"string"},{"path":"document.reference","type":"string"},{"path":"document.asOf","type":"date"},{"path":"entity","type":"object"},{"path":"entity.id","type":"string"},{"path":"entity.code","type":"string"},{"path":"entity.name","type":"string"},{"path":"entity.address","type":"object"},{"path":"entity.address.line1","type":"string"},{"path":"entity.address.line2","type":"string"},{"path":"entity.address.postalCode","type":"string"},{"path":"entity.address.city","type":"string"},{"path":"entity.address.region","type":"string"},{"path":"entity.address.country","type":"string"},{"path":"entity.vatNumber","type":"string"},{"path":"entity.cocNumber","type":"string"},{"path":"entity.iban","type":"string"},{"path":"entity.bic","type":"string"},{"path":"entity.logoAttachmentId","type":"string"},{"path":"entity.defaultCurrency","type":"string"},{"path":"buyer","type":"object"},{"path":"buyer.id","type":"string"},{"path":"buyer.type","type":"string"},{"path":"buyer.name","type":"string"},{"path":"buyer.email","type":"string"},{"path":"buyer.vatNumber","type":"string"},{"path":"buyer.language","type":"string"},{"path":"buyer.address","type":"object"},{"path":"buyer.address.line1","type":"string"},{"path":"buyer.address.line2","type":"string"},{"path":"buyer.address.postalCode","type":"string"},{"path":"buyer.address.city","type":"string"},{"path":"buyer.address.region","type":"string"},{"path":"buyer.address.country","type":"string"},{"path":"lines","type":"list"},{"path":"lines[].position","type":"number"},{"path":"lines[].description","type":"string"},{"path":"lines[].sku","type":"string"},{"path":"lines[].reference","type":"string"},{"path":"lines[].date","type":"date"},{"path":"lines[].dueOn","type":"date"},{"path":"lines[].quantity","type":"string"},{"path":"lines[].unitAmount","type":"money"},{"path":"lines[].discountBps","type":"number"},{"path":"lines[].discountAmount","type":"money"},{"path":"lines[].taxRateBps","type":"number"},{"path":"lines[].taxCode","type":"string"},{"path":"lines[].amount","type":"money"},{"path":"tax_lines","type":"list"},{"path":"tax_lines[].taxRateBps","type":"number"},{"path":"tax_lines[].taxCode","type":"string"},{"path":"tax_lines[].net","type":"money"},{"path":"tax_lines[].tax","type":"money"},{"path":"tax_lines[].gross","type":"money"},{"path":"totals","type":"object"},{"path":"totals.listTotal","type":"money"},{"path":"totals.discountTotal","type":"money"},{"path":"totals.subtotal","type":"money"},{"path":"totals.taxTotal","type":"money"},{"path":"totals.total","type":"money"},{"path":"totals.paidTotal","type":"money"},{"path":"totals.creditedTotal","type":"money"},{"path":"totals.shippingTotal","type":"money"},{"path":"totals.fee","type":"money"},{"path":"totals.balance","type":"money"},{"path":"payment_terms","type":"object"},{"path":"payment_terms.code","type":"string"},{"path":"payment_terms.name","type":"string"},{"path":"payment_terms.days","type":"number"},{"path":"payment_terms.dueOn","type":"date"},{"path":"payment_terms.discountBps","type":"number"},{"path":"payment_terms.discountDays","type":"number"},{"path":"payment_terms.discountDueOn","type":"date"},{"path":"payment_terms.discountAmount","type":"money"},{"path":"texts","type":"object"}]}}'::jsonb;
begin
  if document_template_contract.document_type is null then
    return v_all;
  end if;
  if not v_all ? document_template_contract.document_type then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  return v_all -> document_template_contract.document_type;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_template_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select t."updated_at" from "better_supabase"."document_templates" t where t."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_text_block_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select b."updated_at" from "better_supabase"."document_text_blocks" b where b."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  case document_variables.document_type
    when 'invoice' then return "better_supabase"."document_variables_invoice"(document_variables.tenant, document_id, false);
    when 'credit_note' then return "better_supabase"."document_variables_invoice"(document_variables.tenant, document_id, true);
    when 'quote' then return "better_supabase"."document_variables_quote"(document_variables.tenant, document_id);
    when 'order' then return "better_supabase"."document_variables_order"(document_variables.tenant, document_id);
    when 'delivery_note' then return "better_supabase"."document_variables_delivery_note"(document_variables.tenant, document_id);
    when 'dunning_letter' then return "better_supabase"."document_variables_dunning_letter"(document_variables.tenant, document_id);
    when 'statement' then return "better_supabase"."document_variables_statement"(document_variables.tenant, document_id);
    else
      raise exception 'unknown document type' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables_delivery_note (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."shipments"%rowtype;
  v_lines jsonb;
  v_customer text;
  v_buyer jsonb;
  v_email text;
begin
  select * into v_row from "better_supabase"."shipments" x
    where x."id" = document_variables_delivery_note.document_id and x."tenant_id" = document_variables_delivery_note.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if v_row."subject_type" = 'order' then
    select o."customer_id"::text, o."buyer", o."email"
      into v_customer, v_buyer, v_email
      from "better_supabase"."orders" o
      where o."id"::text = v_row."subject_id" and o."tenant_id" = document_variables_delivery_note.tenant;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', n.sku,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', n.quantity,
      'unitAmount', null::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', null::text
    ) order by n.n), '[]'::jsonb) into v_lines
  from (
    select row_number() over (order by x."position", x."id") as n,
      coalesce(ol."title", x."variant_id"::text) as description,
      ol."sku" as sku,
      trim_scale((x."quantity")::numeric)::text as quantity
    from "better_supabase"."shipment_lines" x
    left join "better_supabase"."order_lines" ol on v_row."subject_type" = 'order' and ol."order_id"::text = v_row."subject_id" and ol."variant_id" = x."variant_id"
    where x."shipment_id" = v_row."id" and x."direction" = 'outbound'
  ) n;
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', 'delivery_note', 'number', v_row."reference", 'title', null::text, 'status', v_row."status"::text, 'date', to_char(coalesce(v_row."labeled_at", v_row."created_at") at time zone 'UTC', 'YYYY-MM-DD'), 'currency', null::text, 'language', null::text, 'note', null::text, 'reference', v_row."tracking_number"),
    'entity', "better_supabase"."document_entity"(document_variables_delivery_note.tenant, (select o.legal_entity_id from "better_supabase"."orders" o where v_row."subject_type" = 'order' and o."id"::text = v_row."subject_id")),
    'buyer', "better_supabase"."document_party"(document_variables_delivery_note.tenant, v_customer, v_customer, v_buyer, v_email, v_row."to_address"),
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', null::text, 'subtotal', null::text, 'taxTotal', null::text, 'total', null::text, 'paidTotal', null::text, 'creditedTotal', null::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', null::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text),
    'shipping', jsonb_build_object('address', "better_supabase"."document_address"(v_row."to_address"), 'carrier', v_row."carrier", 'trackingNumber', v_row."tracking_number")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables_dunning_letter (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_item "better_supabase"."invoice_dunning_run_items"%rowtype;
  v_as_of date;
  v_lines jsonb;
  v_fee bigint;
  v_balance bigint;
  v_level integer;
  v_due date;
  v_currency text;
begin
  select * into v_item from "better_supabase"."invoice_dunning_run_items" x
    where x."id" = document_variables_dunning_letter.document_id and x."tenant_id" = document_variables_dunning_letter.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select x."as_of" into v_as_of from "better_supabase"."invoice_dunning_runs" x where x."id" = v_item."run_id";
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', null::text,
      'reference', n.number,
      'date', n.issued_on,
      'dueOn', n.due_on,
      'quantity', '1',
      'unitAmount', n.balance::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', n.balance::text
    ) order by n.n), '[]'::jsonb),
    coalesce(sum(n.fee), 0), coalesce(sum(n.balance), 0), max(n.level), min(n.due), max(n.currency)
  into v_lines, v_fee, v_balance, v_level, v_due, v_currency
  from (
    select row_number() over (order by x."due_on", x."id") as n,
      coalesce(i."title", i."identifier") as description,
      coalesce(i."identifier", i."number"::text) as number,
      to_char(i."issued_on", 'YYYY-MM-DD') as issued_on,
      to_char(x."due_on", 'YYYY-MM-DD') as due_on,
      x."due_on" as due,
      x."balance" as balance,
      x."fee" as fee,
      x."level" as level,
      trim(i."currency") as currency
    from "better_supabase"."invoice_dunning_run_items" x
    join "better_supabase"."invoices" i on i."id" = x."invoice_id"
    where x."run_id" = v_item."run_id"
      and x."party_id" is not distinct from v_item."party_id"
  ) n;
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_item."id"::text, 'type', 'dunning_letter', 'number', null::text, 'title', null::text, 'status', null::text, 'date', to_char(v_as_of, 'YYYY-MM-DD'), 'currency', v_currency, 'language', null::text, 'note', null::text, 'reference', null::text, 'dueOn', to_char(v_due, 'YYYY-MM-DD'), 'level', v_level, 'asOf', to_char(v_as_of, 'YYYY-MM-DD'), 'textKey', v_item."text_key"),
    'entity', "better_supabase"."document_entity"(document_variables_dunning_letter.tenant, (select x.legal_entity_id from "better_supabase"."invoices" x where x."id" = v_item."invoice_id")),
    'buyer', "better_supabase"."document_party"(document_variables_dunning_letter.tenant, v_item."party_id"::text, null),
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', null::text, 'subtotal', null::text, 'taxTotal', null::text, 'total', (v_balance + v_fee)::bigint::text, 'paidTotal', null::text, 'creditedTotal', null::text, 'shippingTotal', null::text, 'fee', (v_fee)::bigint::text, 'balance', (v_balance + v_fee)::bigint::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables_invoice (
  tenant      uuid,
  document_id uuid,
  credit_note boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."invoices"%rowtype;
  v_lines jsonb;
begin
  select * into v_row from "better_supabase"."invoices" x
    where x."id" = document_variables_invoice.document_id and x."tenant_id" = document_variables_invoice.tenant;
  if not found or v_row."kind" = 'credit_note' is distinct from document_variables_invoice.credit_note then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_lines := (select coalesce(jsonb_agg(jsonb_build_object(
      'position', l.n,
      'description', l."description",
      'sku', null::text,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', trim_scale((l."quantity")::numeric)::text,
      'unitAmount', (l."unit_amount")::bigint::text,
      'discountBps', l."discount_bps",
      'discountAmount', (l."discount_amount")::bigint::text,
      'taxRateBps', l."tax_rate_bps",
      'taxCode', l."tax_code",
      'amount', (round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0))))::bigint::text
    ) order by l.n), '[]'::jsonb)
      from (
        select x.*, row_number() over (order by x."position", x."id") as n
        from "better_supabase"."invoice_lines" x
        where x."parent_id" = v_row."id"
      ) l
      where true);
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', case when document_variables_invoice.credit_note then 'credit_note' else 'invoice' end, 'number', coalesce(v_row."identifier", v_row."number"::text), 'title', v_row."title", 'status', v_row."status"::text, 'date', to_char(v_row."issued_on", 'YYYY-MM-DD'), 'currency', trim(v_row."currency"), 'language', null::text, 'note', v_row."note", 'reference', null::text, 'dueOn', to_char(v_row."due_on", 'YYYY-MM-DD'), 'originalNumber', case when document_variables_invoice.credit_note then (select coalesce(o."identifier", o."number"::text) from "better_supabase"."invoices" o where o."id" = v_row."original_id") end),
    'entity', "better_supabase"."document_entity"(document_variables_invoice.tenant, v_row.legal_entity_id),
    'buyer', "better_supabase"."document_party"(document_variables_invoice.tenant, v_row."company_id"::text, v_row."contact_id"::text, v_row."buyer"),
    'lines', v_lines,
    'tax_lines', (select case when count(*) = 0 then "better_supabase"."document_tax_summary"(v_lines) else jsonb_agg(jsonb_build_object(
      'taxRateBps', x."tax_rate_bps",
      'taxCode', x."tax_code",
      'net', (x."net")::bigint::text,
      'tax', (x."tax")::bigint::text,
      'gross', (x."gross")::bigint::text
    ) order by x."tax_rate_bps", x."tax_code") end
    from "better_supabase"."invoice_tax_lines" x
    where x."invoice_id" = v_row."id"),
    'totals', jsonb_build_object('listTotal', (v_row."list_total")::bigint::text, 'discountTotal', (v_row."discount_total")::bigint::text, 'subtotal', (v_row."subtotal")::bigint::text, 'taxTotal', (v_row."tax_total")::bigint::text, 'total', (v_row."total")::bigint::text, 'paidTotal', (v_row."paid_total")::bigint::text, 'creditedTotal', (v_row."credited_total")::bigint::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', case when document_variables_invoice.credit_note then null else (v_row."total" - v_row."paid_total" - v_row."credited_total")::bigint::text end),
    'payment_terms', jsonb_build_object('code', (select "code"::text from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'name', (select "name"::text from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'days', v_row."terms_days", 'dueOn', to_char(v_row."due_on", 'YYYY-MM-DD'), 'discountBps', (select "discount_bps" from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'discountDays', (select "discount_days" from "better_supabase"."payment_terms" x where x."id" = v_row."payment_terms_id"), 'discountDueOn', to_char(v_row."discount_due_on", 'YYYY-MM-DD'), 'discountAmount', (v_row."discount_amount_early")::bigint::text)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables_order (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."orders"%rowtype;
  v_lines jsonb;
begin
  select * into v_row from "better_supabase"."orders" x
    where x."id" = document_variables_order.document_id and x."tenant_id" = document_variables_order.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', l.n,
      'description', l."title",
      'sku', l."sku",
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', l."quantity"::text,
      'unitAmount', (l."unit_amount")::bigint::text,
      'discountBps', null::integer,
      'discountAmount', (l."discount")::bigint::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', (l."subtotal" - l."discount")::bigint::text
    ) order by l.n), '[]'::jsonb) into v_lines
  from (
    select x.*, row_number() over (order by x."position", x."id") as n
    from "better_supabase"."order_lines" x
    where x."order_id" = v_row."id"
  ) l;
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', 'order', 'number', v_row."number"::text, 'title', null::text, 'status', v_row."status"::text, 'date', to_char(v_row."placed_at" at time zone 'UTC', 'YYYY-MM-DD'), 'currency', trim(v_row."currency"), 'language', null::text, 'note', null::text, 'reference', null::text),
    'entity', "better_supabase"."document_entity"(document_variables_order.tenant, v_row.legal_entity_id),
    'buyer', "better_supabase"."document_party"(document_variables_order.tenant, v_row."customer_id"::text, v_row."customer_id"::text, v_row."buyer", v_row."email", v_row."billing_address"),
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', (v_row."discount_total")::bigint::text, 'subtotal', (v_row."subtotal")::bigint::text, 'taxTotal', (v_row."tax_total")::bigint::text, 'total', (v_row."total")::bigint::text, 'paidTotal', (v_row."paid_total")::bigint::text, 'creditedTotal', (v_row."refunded_total")::bigint::text, 'shippingTotal', (v_row."shipping_total")::bigint::text, 'fee', null::text, 'balance', (v_row."total" - v_row."paid_total" + v_row."refunded_total")::bigint::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text),
    'shipping', jsonb_build_object('address', "better_supabase"."document_address"(v_row."shipping_address"), 'carrier', (select x."carrier"::text from "better_supabase"."order_fulfillments" x where x."order_id" = v_row."id" order by x."created_at" desc limit 1), 'trackingNumber', (select x."tracking_number"::text from "better_supabase"."order_fulfillments" x where x."order_id" = v_row."id" order by x."created_at" desc limit 1))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables_quote (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."quotes"%rowtype;
  v_lines jsonb;
begin
  select * into v_row from "better_supabase"."quotes" x
    where x."id" = document_variables_quote.document_id and x."tenant_id" = document_variables_quote.tenant;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_lines := (select coalesce(jsonb_agg(jsonb_build_object(
      'position', l.n,
      'description', l."description",
      'sku', null::text,
      'reference', null::text,
      'date', null::text,
      'dueOn', null::text,
      'quantity', trim_scale((l."quantity")::numeric)::text,
      'unitAmount', (l."unit_amount")::bigint::text,
      'discountBps', l."discount_bps",
      'discountAmount', (l."discount_amount")::bigint::text,
      'taxRateBps', l."tax_rate_bps",
      'taxCode', l."tax_code",
      'amount', (round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0))))::bigint::text
    ) order by l.n), '[]'::jsonb)
      from (
        select x.*, row_number() over (order by x."position", x."id") as n
        from "better_supabase"."quote_lines" x
        where x."parent_id" = v_row."id"
      ) l
      where (not l."optional" or l."selected"));
  return jsonb_build_object(
    'document', jsonb_build_object('id', v_row."id"::text, 'type', 'quote', 'number', coalesce(v_row."identifier", v_row."number"::text), 'title', v_row."title", 'status', v_row."status"::text, 'date', to_char(coalesce(v_row."sent_at", v_row."created_at") at time zone 'UTC', 'YYYY-MM-DD'), 'currency', trim(v_row."currency"), 'language', null::text, 'note', v_row."note", 'reference', null::text, 'validUntil', to_char(v_row."valid_until", 'YYYY-MM-DD'), 'revision', v_row."revision"),
    'entity', "better_supabase"."document_entity"(document_variables_quote.tenant, v_row.legal_entity_id),
    'buyer', "better_supabase"."document_party"(document_variables_quote.tenant, v_row."company_id"::text, v_row."contact_id"::text, v_row."buyer"),
    'lines', v_lines,
    'tax_lines', (select case when count(*) = 0 then "better_supabase"."document_tax_summary"(v_lines) else jsonb_agg(jsonb_build_object(
      'taxRateBps', x."tax_rate_bps",
      'taxCode', x."tax_code",
      'net', (x."net")::bigint::text,
      'tax', (x."tax")::bigint::text,
      'gross', (x."gross")::bigint::text
    ) order by x."tax_rate_bps", x."tax_code") end
    from "better_supabase"."quote_tax_lines" x
    where x."parent_id" = v_row."id"),
    'totals', jsonb_build_object('listTotal', (v_row."list_total")::bigint::text, 'discountTotal', (v_row."discount_total")::bigint::text, 'subtotal', (v_row."subtotal")::bigint::text, 'taxTotal', (v_row."tax_total")::bigint::text, 'total', (v_row."total")::bigint::text, 'paidTotal', null::text, 'creditedTotal', null::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', null::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', v_row."terms", 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_variables_statement (
  tenant      uuid,
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_lines jsonb;
  v_total bigint;
  v_paid bigint;
  v_credited bigint;
  v_balance bigint;
  v_currency text;
  v_party jsonb;
begin
  v_party := "better_supabase"."document_party"(document_variables_statement.tenant, document_variables_statement.document_id::text, document_variables_statement.document_id::text);
  if v_party ->> 'id' is null then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'position', n.n,
      'description', n.description,
      'sku', null::text,
      'reference', n.number,
      'date', n.issued_on,
      'dueOn', n.due_on,
      'quantity', '1',
      'unitAmount', n.balance::text,
      'discountBps', null::integer,
      'discountAmount', null::text,
      'taxRateBps', null::integer,
      'taxCode', null::text,
      'amount', n.balance::text
    ) order by n.n), '[]'::jsonb),
    coalesce(sum(n.total), 0), coalesce(sum(n.paid), 0), coalesce(sum(n.credited), 0), coalesce(sum(n.balance), 0), max(n.currency)
  into v_lines, v_total, v_paid, v_credited, v_balance, v_currency
  from (
    select row_number() over (order by x."due_on", x."id") as n,
      coalesce(x."title", x."identifier") as description,
      coalesce(x."identifier", x."number"::text) as number,
      to_char(x."issued_on", 'YYYY-MM-DD') as issued_on,
      to_char(x."due_on", 'YYYY-MM-DD') as due_on,
      x."total" as total,
      x."paid_total" as paid,
      x."credited_total" as credited,
      x."total" - x."paid_total" - x."credited_total" as balance,
      trim(x."currency") as currency
    from "better_supabase"."invoices" x
    where x."tenant_id" = document_variables_statement.tenant and (x."company_id"::text = document_variables_statement.document_id::text or x."contact_id"::text = document_variables_statement.document_id::text)
      and x."status" in ('issued', 'partially_paid') and x."kind" = 'invoice' and x."direction" = 'sales'
      and x."total" - x."paid_total" - x."credited_total" > 0
  ) n;
  return jsonb_build_object(
    'document', jsonb_build_object('id', document_variables_statement.document_id::text, 'type', 'statement', 'number', null::text, 'title', null::text, 'status', null::text, 'date', to_char(current_date, 'YYYY-MM-DD'), 'currency', v_currency, 'language', null::text, 'note', null::text, 'reference', null::text, 'asOf', to_char(current_date, 'YYYY-MM-DD')),
    'entity', "better_supabase"."document_entity"(document_variables_statement.tenant, (select x.legal_entity_id from "better_supabase"."invoices" x where (x."company_id"::text = document_variables_statement.document_id::text or x."contact_id"::text = document_variables_statement.document_id::text) order by x."issued_on" desc limit 1)),
    'buyer', v_party,
    'lines', v_lines,
    'tax_lines', '[]'::jsonb,
    'totals', jsonb_build_object('listTotal', null::text, 'discountTotal', null::text, 'subtotal', null::text, 'taxTotal', null::text, 'total', (v_total)::bigint::text, 'paidTotal', (v_paid)::bigint::text, 'creditedTotal', (v_credited)::bigint::text, 'shippingTotal', null::text, 'fee', null::text, 'balance', (v_balance)::bigint::text),
    'payment_terms', jsonb_build_object('code', null::text, 'name', null::text, 'days', null::text, 'dueOn', null::text, 'discountBps', null::text, 'discountDays', null::text, 'discountDueOn', null::text, 'discountAmount', null::text)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_visible (
  tenant        uuid,
  document_type text,
  document_id   uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  case document_visible.document_type
    when 'invoice', 'credit_note' then
      return exists (select 1 from "better_supabase"."invoices" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'quote' then
      return exists (select 1 from "better_supabase"."quotes" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'order' then
      return exists (select 1 from "better_supabase"."orders" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'delivery_note' then
      return exists (select 1 from "better_supabase"."shipments" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    when 'dunning_letter' then
      return exists (select 1 from "better_supabase"."invoice_dunning_run_items" x where x."id" = document_visible.document_id and x."tenant_id" = document_visible.tenant);
    else
      return false;
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.freeze_document (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text DEFAULT NULL::text,
  template_name text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', freeze_document.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if freeze_document.document_type is null or freeze_document.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  return "better_supabase"."document_freeze"(freeze_document.tenant, freeze_document.document_type, freeze_document.document_id, freeze_document.language, freeze_document.template_name);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.freeze_issued_invoice()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if better_supabase.import_run() is not null then
    return null;
  end if;
  begin
    perform "better_supabase"."document_freeze"(new."tenant_id", case when new."kind" = 'credit_note' then 'credit_note' else 'invoice' end, new."id", null, null);
  exception when others then
    raise warning 'the document snapshot of invoice % was skipped: %', new."id", sqlerrm;
  end;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_document_template (
  template_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."document_templates"%rowtype;
begin
  select * into v_row from "better_supabase"."document_templates" t where t."id" = get_document_template.template_id;
  if not found then
    raise exception 'document template not found' using errcode = 'P0002', hint = 'DOCUMENT_TEMPLATE_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['attachment', 'data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'order', 'payment_term', 'document_delivery_preference', 'quote', 'invoice', 'credit_note', 'accounting_account', 'accounting_journal', 'accounting_entry', 'accounting_opening_balance', 'tax_code', 'tax_rate', 'document_template', 'document_text_block', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'order' then
          v_current := "better_supabase"."order_updated_at"(v_rec."subject_id");
        when 'payment_term' then
          v_current := "better_supabase"."payment_term_updated_at"(v_rec."subject_id");
        when 'document_delivery_preference' then
          v_current := "better_supabase"."document_delivery_preference_updated_at"(v_rec."subject_id");
        when 'quote' then
          v_current := "better_supabase"."quote_updated_at"(v_rec."subject_id");
        when 'invoice' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'credit_note' then
          v_current := "better_supabase"."invoice_updated_at"(v_rec."subject_id");
        when 'tax_code' then
          v_current := "better_supabase"."tax_code_updated_at"(v_rec."subject_id");
        when 'document_template' then
          v_current := "better_supabase"."document_template_updated_at"(v_rec."subject_id");
        when 'document_text_block' then
          v_current := "better_supabase"."document_text_block_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
      when 'attachment' then
        v_subject_type := 'attachment';
        v_out := "better_supabase"."import_attachment"(v_run_id, v_call, v_subject_id);
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'order' then
        v_subject_type := 'order';
        v_out := "better_supabase"."import_order"(v_run_id, v_call, v_subject_id);
      when 'payment_term' then
        v_subject_type := 'payment_term';
        v_out := "better_supabase"."import_payment_term"(v_run_id, v_call, v_subject_id);
      when 'document_delivery_preference' then
        v_subject_type := 'document_delivery_preference';
        v_out := "better_supabase"."import_document_delivery_preference"(v_run_id, v_call, v_subject_id);
      when 'quote' then
        v_subject_type := 'quote';
        v_out := "better_supabase"."import_quote"(v_run_id, v_call, v_subject_id);
      when 'invoice' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_invoice"(v_run_id, v_call, v_subject_id);
      when 'credit_note' then
        v_subject_type := 'invoice';
        v_out := "better_supabase"."import_credit_note"(v_run_id, v_call, v_subject_id);
      when 'accounting_account' then
        v_subject_type := 'accounting_account';
        v_out := "better_supabase"."import_accounting_account"(v_run_id, v_call, v_subject_id);
      when 'accounting_journal' then
        v_subject_type := 'accounting_journal';
        v_out := "better_supabase"."import_accounting_journal"(v_run_id, v_call, v_subject_id);
      when 'accounting_entry' then
        v_subject_type := 'accounting_entry';
        v_out := "better_supabase"."import_accounting_entry"(v_run_id, v_call, v_subject_id);
      when 'accounting_opening_balance' then
        v_subject_type := 'accounting_opening_balance';
        v_out := "better_supabase"."import_accounting_opening_balance"(v_run_id, v_call, v_subject_id);
      when 'tax_code' then
        v_subject_type := 'tax_code';
        v_out := "better_supabase"."import_tax_code"(v_run_id, v_call, v_subject_id);
      when 'tax_rate' then
        v_subject_type := 'tax_rate';
        v_out := "better_supabase"."import_tax_rate"(v_run_id, v_call, v_subject_id);
      when 'document_template' then
        v_subject_type := 'document_template';
        v_out := "better_supabase"."import_document_template"(v_run_id, v_call, v_subject_id);
      when 'document_text_block' then
        v_subject_type := 'document_text_block';
        v_out := "better_supabase"."import_document_text_block"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

        v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
        if not exists (
          select 1 from jsonb_array_elements(v_subjects) s
          where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
        ) then
          raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
        end if;

        for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
          if jsonb_typeof(v_subject -> 'warnings') = 'array' then
            v_warnings := v_warnings || (select coalesce(jsonb_agg(w.value || jsonb_build_object('entity', v_entity, 'key', v_key)), '[]'::jsonb) from jsonb_array_elements(v_subject -> 'warnings') w);
          end if;
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors) || case when jsonb_array_length(v_warnings) > 0 then jsonb_build_object('warnings', v_warnings) else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_document_template (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_document_template.item ->> 'tenant')::uuid;
  v_data jsonb := import_document_template.item -> 'data';
  v_entity uuid;
  v_saved jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a template item is an object' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if nullif(v_data ->> 'legalEntityId', '') is not null then
    v_entity := (v_data ->> 'legalEntityId')::uuid;
  elsif nullif(v_data ->> 'legalEntity', '') is not null then
    select x."id" into v_entity from "better_supabase"."legal_entities" x
      where x."tenant_id" = v_tenant and x."code" = v_data ->> 'legalEntity';
    if v_entity is null then
      raise exception 'the legal entity code is unknown' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  v_saved := "better_supabase"."save_document_template"(v_tenant, v_data ->> 'documentType', v_data ->> 'body', v_data ->> 'language',
    coalesce(nullif(v_data ->> 'name', ''), 'default'), v_entity, coalesce((v_data ->> 'active')::boolean, true));
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_document_text_block (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := (import_document_text_block.item ->> 'tenant')::uuid;
  v_data jsonb := import_document_text_block.item -> 'data';
  v_entity uuid;
  v_saved jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a text block item is an object' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if nullif(v_data ->> 'legalEntityId', '') is not null then
    v_entity := (v_data ->> 'legalEntityId')::uuid;
  elsif nullif(v_data ->> 'legalEntity', '') is not null then
    select x."id" into v_entity from "better_supabase"."legal_entities" x
      where x."tenant_id" = v_tenant and x."code" = v_data ->> 'legalEntity';
    if v_entity is null then
      raise exception 'the legal entity code is unknown' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  v_saved := "better_supabase"."save_document_text_block"(v_tenant, v_data ->> 'key', v_data ->> 'body', v_data ->> 'language', v_entity);
  return jsonb_build_object('subjectId', v_saved ->> 'id', 'updatedAt', v_saved -> 'updatedAt');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_document_templates (
  tenant          uuid,
  document_type   text    DEFAULT NULL::text,
  legal_entity_id uuid    DEFAULT NULL::uuid,
  active_only     boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'organizationId', t."tenant_id", 'legalEntityId', t."legal_entity_id", 'documentType', t."document_type", 'language', t."language", 'name', t."name", 'body', t."body", 'version', t."version", 'active', t."active", 'createdAt', t."created_at", 'updatedAt', t."updated_at") order by t."document_type", t."name", t."legal_entity_id" nulls first, t."language" nulls first), '[]'::jsonb)
  from "better_supabase"."document_templates" t
  where t."tenant_id" = list_document_templates.tenant
    and (list_document_templates.document_type is null or t."document_type" = list_document_templates.document_type)
    and (list_document_templates.legal_entity_id is null or t."legal_entity_id" = list_document_templates.legal_entity_id)
    and (not coalesce(list_document_templates.active_only, false) or t."active")
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_document_text_blocks (
  tenant          uuid,
  key             text DEFAULT NULL::text,
  legal_entity_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', b."id", 'organizationId', b."tenant_id", 'legalEntityId', b."legal_entity_id", 'key', b."key", 'language', b."language", 'body', b."body", 'version', b."version", 'createdAt', b."created_at", 'updatedAt', b."updated_at") order by b."key", b."legal_entity_id" nulls first, b."language" nulls first), '[]'::jsonb)
  from "better_supabase"."document_text_blocks" b
  where b."tenant_id" = list_document_text_blocks.tenant
    and (list_document_text_blocks.key is null or b."key" = list_document_text_blocks.key)
    and (list_document_text_blocks.legal_entity_id is null or b."legal_entity_id" = list_document_text_blocks.legal_entity_id)
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

CREATE OR REPLACE FUNCTION better_supabase.render_document (
  tenant        uuid,
  document_type text,
  document_id   uuid,
  language      text    DEFAULT NULL::text,
  fresh         boolean DEFAULT false,
  template_name text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."rendered_documents"%rowtype;
begin
  if render_document.document_type is null or render_document.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  if not coalesce(render_document.fresh, false) then
    select * into v_row from "better_supabase"."rendered_documents" s
      where s."tenant_id" = render_document.tenant
        and s."document_type" = render_document.document_type
        and s."document_id" = render_document.document_id;
    if found then
      return jsonb_build_object('contractVersion', v_row."contract_version", 'documentType', v_row."document_type", 'documentId', v_row."document_id", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'variables', v_row."variables", 'template', v_row."template", 'blocks', v_row."blocks", 'frozen', true, 'frozenAt', v_row."created_at", 'snapshotId', v_row."id");
    end if;
  end if;
  return "better_supabase"."document_render_live"(render_document.tenant, render_document.document_type, render_document.document_id, render_document.language, render_document.template_name);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_document_blocks (
  tenant          uuid,
  keys            text[],
  legal_entity_id uuid   DEFAULT NULL::uuid,
  language        text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_entity uuid;
  v_language text := lower(nullif(btrim(resolve_document_blocks.language), ''));
  v_result jsonb;
begin
  v_entity := "better_supabase"."legal_entity_of"(resolve_document_blocks.tenant, resolve_document_blocks.legal_entity_id);
  select coalesce(jsonb_object_agg(f.key, f.body), '{}'::jsonb) into v_result
  from (
    select distinct on (b."key") b."key" as key, b."body" as body
    from "better_supabase"."document_text_blocks" b
    where b."tenant_id" = resolve_document_blocks.tenant
      and b."key" = any (coalesce(resolve_document_blocks.keys, '{}'::text[]))
      and (b."legal_entity_id" is null or b."legal_entity_id" = v_entity)
    order by b."key", "better_supabase"."document_slot_rank"(b."legal_entity_id", v_entity, b."language", v_language), b."updated_at" desc
  ) f;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.resolve_document_template (
  tenant          uuid,
  document_type   text,
  legal_entity_id uuid DEFAULT NULL::uuid,
  language        text DEFAULT NULL::text,
  name            text DEFAULT 'default'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_entity uuid;
  v_language text := lower(nullif(btrim(resolve_document_template.language), ''));
  v_row "better_supabase"."document_templates"%rowtype;
  v_rank integer;
begin
  v_entity := "better_supabase"."legal_entity_of"(resolve_document_template.tenant, resolve_document_template.legal_entity_id);
  select * into v_row
  from "better_supabase"."document_templates" t
  where t."tenant_id" = resolve_document_template.tenant
    and t."document_type" = resolve_document_template.document_type
    and t."name" = coalesce(resolve_document_template.name, 'default')
    and t."active"
    and (t."legal_entity_id" is null or t."legal_entity_id" = v_entity)
  order by "better_supabase"."document_slot_rank"(t."legal_entity_id", v_entity, t."language", v_language), t."updated_at" desc
  limit 1;
  if not found then
    return null;
  end if;
  v_rank := "better_supabase"."document_slot_rank"(v_row."legal_entity_id", v_entity, v_row."language", v_language);
  return jsonb_build_object(
    'id', v_row."id",
    'name', v_row."name",
    'documentType', v_row."document_type",
    'legalEntityId', v_row."legal_entity_id",
    'language', v_row."language",
    'version', v_row."version",
    'body', v_row."body",
    'source', case v_rank
      when 0 then 'entity_language'
      when 1 then 'entity_language'
      when 2 then 'entity'
      when 3 then 'organization_language'
      when 4 then 'organization_language'
      when 5 then 'organization'
      when 6 then 'entity_other_language'
      else 'organization_other_language' end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_document_template (
  tenant          uuid,
  document_type   text,
  body            text,
  language        text    DEFAULT NULL::text,
  name            text    DEFAULT 'default'::text,
  legal_entity_id uuid    DEFAULT NULL::uuid,
  active          boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."document_templates"%rowtype;
  v_language text := lower(nullif(btrim(save_document_template.language), ''));
  v_name text := coalesce(nullif(btrim(save_document_template.name), ''), 'default');
  v_active boolean := coalesce(save_document_template.active, true);
  v_changed boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_document_template.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if save_document_template.document_type is null or save_document_template.document_type not in ('invoice', 'credit_note', 'quote', 'order', 'dunning_letter', 'delivery_note', 'statement') then
    raise exception 'the document type is invoice, credit_note, quote, order, dunning_letter, delivery_note, statement' using errcode = '22023', hint = 'DOCUMENT_TYPE_INVALID';
  end if;
  if v_name !~ '^[a-z][a-z0-9_-]{0,63}$' then
    raise exception 'a template name is lower case letters, digits, _ and -, from a letter, up to 64 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a language is a code such as nl or nl-NL' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_template.body is null or length(btrim(save_document_template.body)) = 0 or length(save_document_template.body) > 200000 then
    raise exception 'a template body is 1 to 200000 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_template.legal_entity_id is not null then
    perform "better_supabase"."legal_entity_of"(save_document_template.tenant, save_document_template.legal_entity_id);
  end if;
  perform "better_supabase"."assert_document_template"(save_document_template.document_type, save_document_template.body);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_template_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_document_template.tenant, save_document_template.document_type;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('document_templates:' || save_document_template.tenant::text, 0));
  select * into v_row from "better_supabase"."document_templates" t
    where t."tenant_id" = save_document_template.tenant
      and t."document_type" = save_document_template.document_type
      and t."name" = v_name
      and t."legal_entity_id" is not distinct from save_document_template.legal_entity_id
      and t."language" is not distinct from v_language;
  if found then
    v_changed := v_row."body" <> save_document_template.body;
    if not v_changed and v_row."active" = v_active then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    update "better_supabase"."document_templates" t set
      "body" = save_document_template.body,
      "version" = t."version" + case when v_changed then 1 else 0 end,
      "active" = v_active,
      "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('document_template.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.updated',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'updated ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
  else
    insert into "better_supabase"."document_templates" ("tenant_id", "legal_entity_id", "document_type", "language", "name", "body", "active")
    values (save_document_template.tenant, save_document_template.legal_entity_id, save_document_template.document_type, v_language, v_name, save_document_template.body, v_active)
    returning * into v_row;
    perform "better_supabase".emit_event('document_template.created', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.created',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'created ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_template_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_document_text_block (
  tenant          uuid,
  key             text,
  body            text,
  language        text DEFAULT NULL::text,
  legal_entity_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."document_text_blocks"%rowtype;
  v_language text := lower(nullif(btrim(save_document_text_block.language), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_document_text_block.tenant, 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if save_document_text_block.key is null or save_document_text_block.key !~ '^[a-z][a-z0-9_]{0,63}$' then
    raise exception 'a text key is lower case letters, digits and _, from a letter, up to 64 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if v_language is not null and v_language !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a language is a code such as nl or nl-NL' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_text_block.body is null or length(btrim(save_document_text_block.body)) = 0 or length(save_document_text_block.body) > 200000 then
    raise exception 'a text block body is 1 to 200000 characters' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if save_document_text_block.legal_entity_id is not null then
    perform "better_supabase"."legal_entity_of"(save_document_text_block.tenant, save_document_text_block.legal_entity_id);
  end if;
  perform "better_supabase"."assert_document_template"(null, save_document_text_block.body, true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_text_block_save"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using save_document_text_block.tenant, save_document_text_block.key;
    end if;
  end;
  perform pg_advisory_xact_lock(hashtextextended('document_text_blocks:' || save_document_text_block.tenant::text, 0));
  select * into v_row from "better_supabase"."document_text_blocks" b
    where b."tenant_id" = save_document_text_block.tenant
      and b."key" = save_document_text_block.key
      and b."legal_entity_id" is not distinct from save_document_text_block.legal_entity_id
      and b."language" is not distinct from v_language;
  if found then
    if v_row."body" = save_document_text_block.body then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'key', v_row."key", 'language', v_row."language", 'body', v_row."body", 'version', v_row."version", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
    end if;
    update "better_supabase"."document_text_blocks" b set "body" = save_document_text_block.body, "version" = b."version" + 1, "updated_at" = now()
    where b."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('document_text_block.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_text_block.updated',
    category => 'data',
    target_type => 'document_text_block',
    record_id => v_row."id"::text,
    summary => 'updated text block ' || v_row."key" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version")
  );
  else
    insert into "better_supabase"."document_text_blocks" ("tenant_id", "legal_entity_id", "key", "language", "body")
    values (save_document_text_block.tenant, save_document_text_block.legal_entity_id, save_document_text_block.key, v_language, save_document_text_block.body)
    returning * into v_row;
    perform "better_supabase".emit_event('document_text_block.created', jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_text_block.created',
    category => 'data',
    target_type => 'document_text_block',
    record_id => v_row."id"::text,
    summary => 'created text block ' || v_row."key" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'textBlockId', v_row."id", 'key', v_row."key", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'version', v_row."version")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_text_block_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'key', v_row."key", 'language', v_row."language", 'body', v_row."body", 'version', v_row."version", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_document_template_active (
  template_id uuid,
  active      boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."document_templates"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."document_templates" t where t."id" = set_document_template_active.template_id;
  if not found then
    raise exception 'document template not found' using errcode = 'P0002', hint = 'DOCUMENT_TEMPLATE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'document_templates.manage'), false)) then
    raise exception 'not allowed to manage document templates' using errcode = '42501', hint = 'DOCUMENT_TEMPLATE_FORBIDDEN';
  end if;
  if v_row."active" is distinct from coalesce(set_document_template_active.active, true) then
    update "better_supabase"."document_templates" t set "active" = coalesce(set_document_template_active.active, true), "updated_at" = now()
    where t."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('document_template.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version"), 'document-templates/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/document-templates');
  perform better_supabase.audit_event(
    event_type => 'document_template.updated',
    category => 'data',
    target_type => 'document_template',
    record_id => v_row."id"::text,
    summary => 'updated ' || v_row."document_type" || ' template ' || v_row."name" || ' (version ' || v_row."version"::text || ')',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'templateId', v_row."id", 'documentType', v_row."document_type", 'legalEntityId', v_row."legal_entity_id", 'language', v_row."language", 'name', v_row."name", 'version', v_row."version")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'documentType', v_row."document_type", 'language', v_row."language", 'name', v_row."name", 'body', v_row."body", 'version', v_row."version", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.validate_document_template (
  document_type text,
  body          text,
  text_block    boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_known jsonb := '{}'::jsonb;
  v_contract jsonb;
  v_item jsonb;
  v_parse jsonb := '[]'::jsonb;
  v_check jsonb := '[]'::jsonb;
  v_stack jsonb := '[]'::jsonb;
  v_scope jsonb := '{}'::jsonb;
  v_piece text;
  v_tag text;
  v_match text[];
  v_top jsonb;
  v_path text;
  v_kind text;
  v_head text;
  v_list text;
  v_each text[];
  v_if text[];
  v_value text[];
  v_filter text;
  v_text boolean := not coalesce(validate_document_template.text_block, false);
begin
  if validate_document_template.body is null then
    raise exception 'a template needs a body' using errcode = '22023', hint = 'DOCUMENT_TEMPLATE_INVALID';
  end if;
  if coalesce(validate_document_template.text_block, false) then
    for v_contract in select c.value from jsonb_each("better_supabase"."document_template_contract"(null)) c loop
      for v_item in select e.value from jsonb_array_elements(v_contract -> 'variables') e loop
        v_known := v_known || jsonb_build_object(v_item ->> 'path', v_item ->> 'type');
      end loop;
    end loop;
  else
    for v_item in select e.value from jsonb_array_elements("better_supabase"."document_template_contract"(validate_document_template.document_type) -> 'variables') e loop
      v_known := v_known || jsonb_build_object(v_item ->> 'path', v_item ->> 'type');
    end loop;
  end if;

  -- Text between the tags holds no brace pair.
  for v_piece in select p from regexp_split_to_table(validate_document_template.body, '\{\{[\s\S]*?\}\}') p loop
    if v_piece ~ '\{\{|\}\}' then
      v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'a brace pair is not closed or not opened', 'tag', btrim(v_piece)));
    end if;
  end loop;

  for v_match in select m from regexp_matches(validate_document_template.body, '\{\{([\s\S]*?)\}\}', 'g') m loop
    v_tag := btrim(v_match[1]);
    v_top := case when jsonb_array_length(v_stack) = 0 then null else v_stack -> (jsonb_array_length(v_stack) - 1) end;

    if v_tag in ('/each', '/if') then
      if v_top is null or v_top ->> 'kind' <> substr(v_tag, 2) then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', v_tag || ' closes nothing', 'tag', v_tag));
      else
        v_stack := v_stack - (jsonb_array_length(v_stack) - 1);
        if v_top ->> 'kind' = 'each' then
          v_scope := v_scope - (v_top ->> 'alias');
        end if;
      end if;
    elsif v_tag = 'else' then
      if v_top is null or v_top ->> 'kind' <> 'if' or (v_top ->> 'else')::boolean then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'else belongs inside one #if', 'tag', v_tag));
      else
        v_stack := jsonb_set(v_stack, array[(jsonb_array_length(v_stack) - 1)::text, 'else'], 'true'::jsonb);
      end if;
    else
      v_each := regexp_match(v_tag, '^#each\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\s+as\s+([a-z][A-Za-z0-9_]*)$');
      v_if := regexp_match(v_tag, '^#if\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)$');
      if v_each is not null then
        if coalesce(v_known ->> v_each[1], '') <> 'list' or v_scope ? v_each[1] then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_each[1] || ' is not a list of this document', 'tag', v_each[1]));
        end if;
        if v_known ? v_each[2] or v_scope ? v_each[2] then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', v_each[2] || ' is already a variable', 'tag', v_each[2]));
        end if;
        v_stack := v_stack || jsonb_build_array(jsonb_build_object('kind', 'each', 'alias', v_each[2], 'else', false));
        v_scope := v_scope || jsonb_build_object(v_each[2], v_each[1]);
      elsif v_if is not null then
        v_path := v_if[1];
        v_kind := null;
        v_head := split_part(v_path, '.', 1);
        if v_scope ? v_head then
          v_kind := case when position('.' in v_path) = 0 then null else v_known ->> ((v_scope ->> v_head) || '[]' || substr(v_path, length(v_head) + 1)) end;
        elsif v_path ~ '^texts\.[a-z][a-z0-9_]{0,63}$' then
          v_kind := case when v_text then 'string' else null end;
        else
          v_kind := v_known ->> v_path;
        end if;
        if v_kind is null then
          v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a variable of this document', 'tag', v_path));
        end if;
        v_stack := v_stack || jsonb_build_array(jsonb_build_object('kind', 'if', 'else', false));
      elsif left(v_tag, 1) in ('#', '/') then
        v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'unknown block tag', 'tag', v_tag));
      else
        v_value := regexp_match(v_tag, '^([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)(?:\s*\|\s*([A-Za-z_]+))?$');
        if v_value is null then
          v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', 'a placeholder is a path with an optional filter', 'tag', v_tag));
        else
          v_filter := v_value[2];
          if v_filter is not null and v_filter not in ('money', 'date') then
            v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_FILTER', 'message', 'unknown filter ' || v_filter || '; use money or date', 'tag', v_tag));
          else
            v_path := v_value[1];
            v_kind := null;
            v_head := split_part(v_path, '.', 1);
            if v_scope ? v_head then
              v_kind := case when position('.' in v_path) = 0 then null else v_known ->> ((v_scope ->> v_head) || '[]' || substr(v_path, length(v_head) + 1)) end;
            elsif v_path ~ '^texts\.[a-z][a-z0-9_]{0,63}$' then
              v_kind := case when v_text then 'string' else null end;
            else
              v_kind := v_known ->> v_path;
            end if;
            if v_kind is null then
              v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a variable of this document', 'tag', v_path));
            elsif v_kind in ('object', 'list') then
              v_check := v_check || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE', 'message', v_path || ' is not a single value', 'tag', v_path));
            end if;
          end if;
        end if;
      end if;
    end if;
  end loop;

  for v_item in select s.value from jsonb_array_elements(v_stack) s loop
    v_parse := v_parse || jsonb_build_array(jsonb_build_object('code', 'DOCUMENT_TEMPLATE_SYNTAX', 'message', '#' || (v_item ->> 'kind') || ' is not closed', 'tag', '#' || (v_item ->> 'kind')));
  end loop;

  return v_parse || v_check;
end;
$function$;

ALTER TABLE "better_supabase"."document_templates"
  ADD CONSTRAINT "document_templates_tenant_id_legal_entity_id_fkey" FOREIGN KEY (tenant_id, legal_entity_id) REFERENCES better_supabase.legal_entities(tenant_id, id)
    ON DELETE RESTRICT;

ALTER TABLE "better_supabase"."document_text_blocks"
  ADD CONSTRAINT "document_text_blocks_tenant_id_legal_entity_id_fkey" FOREIGN KEY (tenant_id, legal_entity_id) REFERENCES better_supabase.legal_entities(tenant_id, id)
    ON DELETE RESTRICT;

CREATE INDEX document_templates_entity_idx ON better_supabase.document_templates USING btree (tenant_id, legal_entity_id)
  WHERE (legal_entity_id IS NOT NULL);

CREATE INDEX document_templates_lookup_idx ON better_supabase.document_templates USING btree (tenant_id, document_type, name)
  WHERE active;

CREATE UNIQUE INDEX document_templates_slot_idx ON better_supabase.document_templates
  USING btree (tenant_id, document_type, name, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(LANGUAGE, ''::text));

CREATE INDEX document_text_blocks_entity_idx ON better_supabase.document_text_blocks USING btree (tenant_id, legal_entity_id)
  WHERE (legal_entity_id IS NOT NULL);

CREATE UNIQUE INDEX document_text_blocks_slot_idx ON better_supabase.document_text_blocks
  USING btree (tenant_id, key, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(LANGUAGE, ''::text));

CREATE CONSTRAINT TRIGGER bsb_document_freeze
  AFTER UPDATE OF status ON better_supabase.invoices DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW
  WHEN (((old.status = 'draft'::text) AND (new.status <> ALL (ARRAY['draft'::text, 'void'::text]))))
  EXECUTE FUNCTION better_supabase.freeze_issued_invoice();

CREATE TRIGGER bsb_frozen_render_guard
  BEFORE UPDATE ON better_supabase.rendered_documents
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.document_snapshot_immutable();

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."document_templates"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."document_templates"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."document_templates"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('document_templates.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."document_templates"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "document_templates_read" ON "better_supabase"."document_templates"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('document_templates.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."document_text_blocks"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."document_text_blocks"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."document_text_blocks"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('document_templates.read'::text) AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."document_text_blocks"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "document_text_blocks_read" ON "better_supabase"."document_text_blocks"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('document_templates.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."rendered_documents"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."rendered_documents"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."rendered_documents"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('document_templates.read'::text) AS tenant_ids_with)) AND
CASE
    WHEN (document_type = 'statement'::text) THEN (tenant_id IN ( SELECT better_supabase.tenant_ids_with('document_templates.manage'::text) AS tenant_ids_with))
    ELSE better_supabase.document_visible(tenant_id, document_type, document_id)
END)));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."rendered_documents"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "rendered_documents_read" ON "better_supabase"."rendered_documents"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('document_templates.read'::text) AS tenant_ids_with)) AND
CASE
    WHEN (document_type = 'statement'::text) THEN (tenant_id IN ( SELECT better_supabase.tenant_ids_with('document_templates.manage'::text) AS tenant_ids_with))
    ELSE better_supabase.document_visible(tenant_id, document_type, document_id)
END));

REVOKE ALL ON FUNCTION "api"."document_address"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_address"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_entity"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_entity"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_party"(uuid, text, text, jsonb, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_party"(uuid, text, text, jsonb, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_render_live"(uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_render_live"(uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_slot_rank"(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_slot_rank"(uuid, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_tax_summary"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_tax_summary"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_template_contract"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_template_contract"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_template_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_template_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."document_text_block_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_text_block_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."document_variables"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_variables_delivery_note"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables_delivery_note"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_variables_dunning_letter"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables_dunning_letter"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_variables_invoice"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables_invoice"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_variables_order"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables_order"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_variables_quote"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables_quote"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_variables_statement"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_variables_statement"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."document_visible"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."document_visible"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."freeze_document"(uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."freeze_document"(uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_document_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_document_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_document_template"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_document_template"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_document_text_block"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_document_text_block"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_document_templates"(uuid, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_document_templates"(uuid, text, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_document_text_blocks"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_document_text_blocks"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."render_document"(uuid, text, uuid, text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."render_document"(uuid, text, uuid, text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_document_blocks"(uuid, text[], uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_document_blocks"(uuid, text[], uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."resolve_document_template"(uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."resolve_document_template"(uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_document_template"(uuid, text, text, text, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_document_template"(uuid, text, text, text, text, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_document_text_block"(uuid, text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_document_text_block"(uuid, text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_document_template_active"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_document_template_active"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."validate_document_template"(text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."validate_document_template"(text, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."assert_document_template"(text, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."document_address"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_address"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_entity"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_entity"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_freeze"(uuid, text, uuid, text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."document_party"(uuid, text, text, jsonb, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_party"(uuid, text, text, jsonb, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_render_live"(uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_render_live"(uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_slot_rank"(uuid, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_slot_rank"(uuid, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_snapshot_immutable"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."document_tax_summary"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_tax_summary"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_template_contract"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_template_contract"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_template_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_template_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_text_block_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_text_block_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables_delivery_note"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables_delivery_note"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables_dunning_letter"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables_dunning_letter"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables_invoice"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables_invoice"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables_order"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables_order"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables_quote"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables_quote"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_variables_statement"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_variables_statement"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."document_visible"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."document_visible"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."freeze_document"(uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."freeze_document"(uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."freeze_issued_invoice"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."get_document_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_document_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_document_template"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_document_template"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_document_text_block"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_document_text_block"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_document_templates"(uuid, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_document_templates"(uuid, text, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_document_text_blocks"(uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_document_text_blocks"(uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."render_document"(uuid, text, uuid, text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."render_document"(uuid, text, uuid, text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_document_blocks"(uuid, text[], uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_document_blocks"(uuid, text[], uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."resolve_document_template"(uuid, text, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."resolve_document_template"(uuid, text, uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_document_template"(uuid, text, text, text, text, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_document_template"(uuid, text, text, text, text, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_document_text_block"(uuid, text, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_document_text_block"(uuid, text, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_document_template_active"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_document_template_active"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."validate_document_template"(text, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."validate_document_template"(text, text, boolean) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."document_templates" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."document_templates" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."document_text_blocks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."document_text_blocks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."rendered_documents" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."rendered_documents" TO "service_role";

ALTER TABLE "better_supabase"."document_templates"
  ADD CONSTRAINT "document_templates_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX document_templates_created_by_idx ON better_supabase.document_templates USING btree (created_by)
  WHERE (created_by IS NOT NULL);

ALTER TABLE "better_supabase"."document_text_blocks"
  ADD CONSTRAINT "document_text_blocks_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX document_text_blocks_created_by_idx ON better_supabase.document_text_blocks USING btree (created_by)
  WHERE (created_by IS NOT NULL);

ALTER TABLE "better_supabase"."rendered_documents"
  ADD CONSTRAINT "rendered_documents_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX rendered_documents_created_by_idx ON better_supabase.rendered_documents USING btree (created_by)
  WHERE (created_by IS NOT NULL);
