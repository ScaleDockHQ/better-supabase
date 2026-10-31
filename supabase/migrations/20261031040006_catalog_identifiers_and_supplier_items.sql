SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."product_identifiers" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "variant_id" uuid                     NOT NULL,
  "type"       text                     NOT NULL,
  "value"      text                     NOT NULL,
  "party_id"   uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "product_identifiers_pkey" PRIMARY KEY (id),
  CONSTRAINT "product_identifiers_type_check" CHECK ((type = ANY (ARRAY['ean'::text, 'supplier'::text, 'manufacturer'::text, 'other'::text]))),
  CONSTRAINT "product_identifiers_value_check" CHECK (((length(value) >= 1) AND (length(value) <= 100)))
);

ALTER TABLE "better_supabase"."product_identifiers"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."product_relations" (
  "tenant_id"       uuid                     NOT NULL,
  "from_variant_id" uuid                     NOT NULL,
  "to_variant_id"   uuid                     NOT NULL,
  "kind"            text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "product_relations_check" CHECK ((from_variant_id <> to_variant_id)),
  CONSTRAINT "product_relations_kind_check" CHECK ((kind = ANY (ARRAY['alternative'::text, 'superseded_by'::text, 'accessory'::text]))),
  CONSTRAINT "product_relations_pkey" PRIMARY KEY (from_variant_id, to_variant_id, kind)
);

ALTER TABLE "better_supabase"."product_relations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."supplier_item_mappings" (
  "tenant_id"   uuid                     NOT NULL,
  "supplier_id" uuid                     NOT NULL,
  "columns"     jsonb                    NOT NULL,
  "defaults"    jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "supplier_item_mappings_columns_check" CHECK ((jsonb_typeof(columns) = 'object'::text)),
  CONSTRAINT "supplier_item_mappings_defaults_check" CHECK ((jsonb_typeof(defaults) = 'object'::text)),
  CONSTRAINT "supplier_item_mappings_pkey" PRIMARY KEY (tenant_id, supplier_id)
);

ALTER TABLE "better_supabase"."supplier_item_mappings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."supplier_items" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"     uuid                     NOT NULL,
  "supplier_id"   uuid                     NOT NULL,
  "code"          text                     NOT NULL,
  "description"   text,
  "price"         bigint,
  "currency"      character(3),
  "unit"          text,
  "keywords_text" text,
  "keywords"      tsvector                 GENERATED ALWAYS AS
    (to_tsvector('simple'::regconfig, ((((code || ' '::text) || COALESCE(description, ''::text)) || ' '::text) || COALESCE(keywords_text, ''::text)))) STORED,
  "variant_id"    uuid,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "supplier_items_code_check" CHECK (((length(code) >= 1) AND (length(code) <= 100))),
  CONSTRAINT "supplier_items_currency_check" CHECK ((currency ~ '^[A-Z]{3}$'::text)),
  CONSTRAINT "supplier_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "supplier_items_price_check" CHECK ((price >= 0)),
  CONSTRAINT "supplier_items_tenant_id_supplier_id_code_key" UNIQUE (tenant_id, supplier_id, code)
);

ALTER TABLE "better_supabase"."supplier_items"
  ENABLE ROW LEVEL SECURITY;

ALTER TABLE "better_supabase"."inventory_locations"
  ADD COLUMN "address" jsonb;

ALTER TABLE "better_supabase"."product_variants"
  ADD COLUMN "trade_code" text;

CREATE OR REPLACE FUNCTION api.delete_product_identifier (
  identifier uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_product_identifier"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_product_relation (
  from_variant uuid,
  to_variant   uuid,
  kind         text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_product_relation"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.delete_supplier_item (
  item uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_supplier_item"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_supplier_item_mapping (
  tenant   uuid,
  supplier uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_supplier_item_mapping"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.find_variants_by_identifier (
  tenant uuid,
  value  text,
  type   text DEFAULT NULL::text,
  party  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."find_variants_by_identifier"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.import_product_identifier (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_product_identifier"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.import_supplier_item (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_supplier_item"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.product_identifier_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."product_identifier_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.promote_supplier_item (
  item uuid,
  sku  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."promote_supplier_item"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.replacement_variant (
  variant uuid
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."replacement_variant"($1) $function$;

CREATE OR REPLACE FUNCTION api.save_product_identifier (
  tenant  uuid,
  variant uuid,
  type    text,
  value   text,
  party   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_product_identifier"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_product_relation (
  tenant       uuid,
  from_variant uuid,
  to_variant   uuid,
  kind         text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_product_relation"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.save_supplier_item (
  tenant      uuid,
  item        uuid,
  supplier    uuid,
  code        text,
  description text,
  price       bigint,
  currency    text,
  unit        text,
  keywords    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_supplier_item"($1, $2, $3, $4, $5, $6, $7, $8, $9) $function$;

CREATE OR REPLACE FUNCTION api.search_supplier_items (
  tenant    uuid,
  query     text,
  supplier  uuid    DEFAULT NULL::uuid,
  row_limit integer DEFAULT 25
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."search_supplier_items"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_location_address (
  location uuid,
  address  jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_location_address"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_supplier_item_mapping (
  tenant   uuid,
  supplier uuid,
  columns  jsonb,
  defaults jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_supplier_item_mapping"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_variant_trade_code (
  variant    uuid,
  trade_code text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_variant_trade_code"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.supplier_item_from_row (
  tenant   uuid,
  supplier uuid,
  source   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_item_from_row"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.supplier_item_mapping (
  tenant   uuid,
  supplier uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_item_mapping"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.supplier_item_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."supplier_item_updated_at"($1) $function$;

CREATE OR REPLACE FUNCTION api.variant_identifiers (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."variant_identifiers"($1) $function$;

CREATE OR REPLACE FUNCTION api.variant_relations (
  variant uuid,
  kind    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."variant_relations"($1, $2) $function$;

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
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_product_identifier (
  identifier uuid
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_identifiers" x where x."id" = delete_product_identifier.identifier;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."product_identifiers" x where x."id" = delete_product_identifier.identifier;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_product_relation (
  from_variant uuid,
  to_variant   uuid,
  kind         text
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_relations" x
  where x."from_variant_id" = delete_product_relation.from_variant and x."to_variant_id" = delete_product_relation.to_variant and x."kind" = delete_product_relation.kind;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."product_relations" x
  where x."from_variant_id" = delete_product_relation.from_variant and x."to_variant_id" = delete_product_relation.to_variant and x."kind" = delete_product_relation.kind;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_supplier_item (
  item uuid
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
  select x."tenant_id" into v_tenant from "better_supabase"."supplier_items" x where x."id" = delete_supplier_item.item;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."supplier_items" x where x."id" = delete_supplier_item.item;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_supplier_item_mapping (
  tenant   uuid,
  supplier uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', delete_supplier_item_mapping.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."supplier_item_mappings" x where x."tenant_id" = delete_supplier_item_mapping.tenant and x."supplier_id" = delete_supplier_item_mapping.supplier;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.find_variants_by_identifier (
  tenant uuid,
  value  text,
  type   text DEFAULT NULL::text,
  party  uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('identifierId', x."id", 'variantId', y."id", 'productId', y."product_id", 'sku', y."sku", 'type', x."type", 'value', x."value", 'partyId', x."party_id") order by y."sku", x."type"), '[]'::jsonb)
  from "better_supabase"."product_identifiers" x join "better_supabase"."product_variants" y on y."id" = x."variant_id"
  where x."tenant_id" = $1 and x."value" = btrim($2)
    and ($3 is null or x."type" = $3)
    and ($4 is null or x."party_id" = $4)
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
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['supplier_item', 'product_identifier', 'customer']::text[]) then
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
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
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

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_product_identifier (
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
  v_tenant uuid := (import_product_identifier.item ->> 'tenant')::uuid;
  v_data jsonb := import_product_identifier.item -> 'data';
  v_variant uuid;
  v_type text := v_data ->> 'type';
  v_value text := btrim(v_data ->> 'value');
  v_party uuid;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_variant := nullif(v_data ->> 'variantId', '')::uuid;
    v_party := nullif(v_data ->> 'partyId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'variantId and partyId must be uuids' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_variant is null and nullif(v_data ->> 'sku', '') is not null then
    select y."id" into v_variant from "better_supabase"."product_variants" y where y."tenant_id" = v_tenant and y."sku" = v_data ->> 'sku';
  end if;
  if v_variant is null or not exists (select 1 from "better_supabase"."product_variants" y where y."id" = v_variant and y."tenant_id" = v_tenant) then
    raise exception 'the variant isn''t in this organization; name it with sku or variantId' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_type is null or v_type not in ('ean', 'supplier', 'manufacturer', 'other') then
    raise exception 'the type must be one of ean, supplier, manufacturer, other' using errcode = '22023', hint = 'CATALOG_IDENTIFIER_TYPE_INVALID';
  end if;
  if v_value is null or length(v_value) not between 1 and 100 then
    raise exception 'the value must be 1 to 100 characters' using errcode = '22023', hint = 'CATALOG_IDENTIFIER_INVALID';
  end if;
  if v_type = 'ean' and v_value !~ '^([0-9]{8}|[0-9]{12,14})$' then
    raise exception 'an EAN has 8, 12, 13 or 14 digits' using errcode = '22023', hint = 'CATALOG_IDENTIFIER_INVALID';
  end if;
  if import_product_identifier.subject_id is null then
    insert into "better_supabase"."product_identifiers" as x ("tenant_id", "variant_id", "type", "value", "party_id")
    values (v_tenant, v_variant, v_type, v_value, v_party)
    on conflict ("variant_id", "type", "value", coalesce("party_id", '00000000-0000-0000-0000-000000000000'::uuid)) do update set "updated_at" = now()
    returning x."id", x."updated_at" into v_id, v_updated;
  else
    update "better_supabase"."product_identifiers" x set "variant_id" = v_variant, "type" = v_type, "value" = v_value, "party_id" = v_party, "updated_at" = now()
    where x."id" = import_product_identifier.subject_id::uuid and x."tenant_id" = v_tenant
    returning x."id", x."updated_at" into v_id, v_updated;
    if not found then
      raise exception 'the identifier no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_supplier_item (
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
  v_tenant uuid := (import_supplier_item.item ->> 'tenant')::uuid;
  v_data jsonb := import_supplier_item.item -> 'data';
  v_supplier uuid;
  v_merged jsonb;
  v_code text;
  v_price text;
  v_id uuid;
  v_updated timestamptz;
begin
  begin
    v_supplier := nullif(v_data ->> 'supplierId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'supplierId must be a uuid' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_supplier is null then
    raise exception 'a supplier item needs a supplierId' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_merged := (case when jsonb_typeof(v_data -> 'row') = 'object' then "better_supabase"."supplier_item_from_row"(v_tenant, v_supplier, v_data -> 'row') else '{}'::jsonb end) || (v_data - 'row' - 'supplierId');
  v_code := nullif(btrim(v_merged ->> 'code'), '');
  v_price := v_merged ->> 'price';
  if v_code is null or length(v_code) > 100 then
    raise exception 'a supplier item needs a code of up to 100 characters' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_price is not null and v_price !~ '^[0-9]{1,18}$' then
    raise exception 'price is a whole number of minor units' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_merged ->> 'currency' is not null and "better_supabase"."currency_minor_units"(upper(v_merged ->> 'currency')) is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_supplier_item.subject_id is null then
    insert into "better_supabase"."supplier_items" as x ("tenant_id", "supplier_id", "code", "description", "price", "currency", "unit", "keywords_text")
    values (v_tenant, v_supplier, v_code, v_merged ->> 'description', v_price::bigint, upper(v_merged ->> 'currency'), v_merged ->> 'unit', v_merged ->> 'keywords')
    on conflict ("tenant_id", "supplier_id", "code") do update set "description" = excluded."description", "price" = excluded."price",
      "currency" = excluded."currency", "unit" = excluded."unit", "keywords_text" = excluded."keywords_text", "updated_at" = now()
    returning x."id", x."updated_at" into v_id, v_updated;
  else
    update "better_supabase"."supplier_items" x set "supplier_id" = v_supplier, "code" = v_code, "description" = v_merged ->> 'description', "price" = v_price::bigint,
      "currency" = upper(v_merged ->> 'currency'), "unit" = v_merged ->> 'unit', "keywords_text" = v_merged ->> 'keywords', "updated_at" = now()
    where x."id" = import_supplier_item.subject_id::uuid and x."tenant_id" = v_tenant
    returning x."id", x."updated_at" into v_id, v_updated;
    if not found then
      raise exception 'the supplier item no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_updated);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.product_identifier_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."product_identifiers" x where x."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.promote_supplier_item (
  item uuid,
  sku  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_item "better_supabase"."supplier_items";
  v_sku text;
  v_slug text;
  v_product uuid;
  v_variant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_item from "better_supabase"."supplier_items" x where x."id" = promote_supplier_item.item for update;
  if not found then
    raise exception 'supplier item not found' using errcode = 'P0002', hint = 'CATALOG_SUPPLIER_ITEM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_item."tenant_id", 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_item."variant_id" is not null then
    select y."product_id" into v_product from "better_supabase"."product_variants" y where y."id" = v_item."variant_id";
    return jsonb_build_object('productId', v_product, 'variantId', v_item."variant_id", 'created', false);
  end if;
  v_sku := btrim(coalesce(nullif(promote_supplier_item.sku, ''), v_item."code"));
  if length(v_sku) not between 1 and 100 then
    raise exception 'the SKU must be 1 to 100 characters' using errcode = '22023', hint = 'CATALOG_SKU_INVALID';
  end if;
  v_slug := trim(both '-' from regexp_replace(lower(v_sku), '[^a-z0-9]+', '-', 'g'));
  if v_slug = '' then
    v_slug := 'item';
  end if;
  if exists (select 1 from "better_supabase"."products" x where x."tenant_id" = v_item."tenant_id" and x."slug" = v_slug) then
    v_slug := v_slug || '-' || substr(v_item."id"::text, 1, 8);
  end if;
  begin
    insert into "better_supabase"."products" as x ("tenant_id", "title", "slug", "description")
    values (v_item."tenant_id", left(coalesce(nullif(v_item."description", ''), v_item."code"), 500), v_slug, v_item."description")
    returning x."id" into v_product;
    insert into "better_supabase"."product_variants" as y ("tenant_id", "product_id", "sku")
    values (v_item."tenant_id", v_product, v_sku)
    returning y."id" into v_variant;
  exception when unique_violation then
    raise exception 'another variant has this SKU' using errcode = '23505', hint = 'CATALOG_SKU_TAKEN';
  end;
  update "better_supabase"."supplier_items" x set "variant_id" = v_variant, "updated_at" = now() where x."id" = v_item."id";
  insert into "better_supabase"."product_identifiers" ("tenant_id", "variant_id", "type", "value", "party_id")
  values (v_item."tenant_id", v_variant, 'supplier', v_item."code", v_item."supplier_id")
  on conflict do nothing;
  perform "better_supabase".emit_event('product.created', jsonb_build_object('organizationId', v_item."tenant_id", 'id', v_product, 'slug', v_slug, 'kind', null), 'products/' || v_product::text, (v_item."tenant_id")::text, null, 'better-supabase/catalog');
  perform "better_supabase".emit_event('product_variant.created', jsonb_build_object('organizationId', v_item."tenant_id", 'id', v_variant, 'productId', v_product, 'sku', v_sku), 'variants/' || v_variant::text, (v_item."tenant_id")::text, null, 'better-supabase/catalog');
  return jsonb_build_object('productId', v_product, 'variantId', v_variant, 'created', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.replacement_variant (
  variant uuid
)
  RETURNS uuid
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with recursive chain(id, depth) as (
    select $1, 0
    union all
    select x."to_variant_id", c.depth + 1 from "better_supabase"."product_relations" x join chain c on x."from_variant_id" = c.id and x."kind" = 'superseded_by' where c.depth < 50
  )
  select id from chain order by depth desc, id limit 1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_product_identifier (
  tenant  uuid,
  variant uuid,
  type    text,
  value   text,
  party   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_created boolean := false;
  v_value text := btrim(save_product_identifier.value);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_product_identifier.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if save_product_identifier.type is null or save_product_identifier.type not in ('ean', 'supplier', 'manufacturer', 'other') then
    raise exception 'the type must be one of ean, supplier, manufacturer, other' using errcode = '22023', hint = 'CATALOG_IDENTIFIER_TYPE_INVALID';
  end if;
  if v_value is null or length(v_value) not between 1 and 100 then
    raise exception 'the value must be 1 to 100 characters' using errcode = '22023', hint = 'CATALOG_IDENTIFIER_INVALID';
  end if;
  if save_product_identifier.type = 'ean' and v_value !~ '^([0-9]{8}|[0-9]{12,14})$' then
    raise exception 'an EAN has 8, 12, 13 or 14 digits' using errcode = '22023', hint = 'CATALOG_IDENTIFIER_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."product_variants" x where x."id" = save_product_identifier.variant and x."tenant_id" = save_product_identifier.tenant) then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  select x."id" into v_id from "better_supabase"."product_identifiers" x
  where x."variant_id" = save_product_identifier.variant and x."type" = save_product_identifier.type and x."value" = v_value
    and coalesce(x."party_id", '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(save_product_identifier.party, '00000000-0000-0000-0000-000000000000'::uuid);
  if v_id is null then
    begin
      insert into "better_supabase"."product_identifiers" as x ("tenant_id", "variant_id", "type", "value", "party_id")
      values (save_product_identifier.tenant, save_product_identifier.variant, save_product_identifier.type, v_value, save_product_identifier.party)
      returning x."id" into v_id;
      v_created := true;
    exception when unique_violation then
      select x."id" into v_id from "better_supabase"."product_identifiers" x
      where x."variant_id" = save_product_identifier.variant and x."type" = save_product_identifier.type and x."value" = v_value
        and coalesce(x."party_id", '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(save_product_identifier.party, '00000000-0000-0000-0000-000000000000'::uuid);
    end;
  end if;
  return jsonb_build_object('id', v_id, 'created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_product_relation (
  tenant       uuid,
  from_variant uuid,
  to_variant   uuid,
  kind         text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_created boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_product_relation.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if save_product_relation.kind is null or save_product_relation.kind not in ('alternative', 'superseded_by', 'accessory') then
    raise exception 'the kind must be one of alternative, superseded_by, accessory' using errcode = '22023', hint = 'CATALOG_RELATION_KIND_INVALID';
  end if;
  if save_product_relation.from_variant = save_product_relation.to_variant then
    raise exception 'a variant can''t relate to itself' using errcode = '22023', hint = 'CATALOG_RELATION_INVALID';
  end if;
  if (select count(*) from "better_supabase"."product_variants" x where x."tenant_id" = save_product_relation.tenant and x."id" in (save_product_relation.from_variant, save_product_relation.to_variant)) <> 2 then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  if save_product_relation.kind = 'superseded_by' and exists (
    with recursive chain(id, depth) as (
      select save_product_relation.to_variant, 0
      union all
      select y."to_variant_id", c.depth + 1 from "better_supabase"."product_relations" y join chain c on y."from_variant_id" = c.id and y."kind" = 'superseded_by' where c.depth < 50
    )
    select 1 from chain where id = save_product_relation.from_variant
  ) then
    raise exception 'the replacement already points back at this variant' using errcode = '22023', hint = 'CATALOG_RELATION_CYCLE';
  end if;
  insert into "better_supabase"."product_relations" ("tenant_id", "from_variant_id", "to_variant_id", "kind")
  values (save_product_relation.tenant, save_product_relation.from_variant, save_product_relation.to_variant, save_product_relation.kind)
  on conflict do nothing;
  v_created := found;
  return jsonb_build_object('created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_supplier_item (
  tenant      uuid,
  item        uuid,
  supplier    uuid,
  code        text,
  description text,
  price       bigint,
  currency    text,
  unit        text,
  keywords    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_supplier_item.item;
  v_code text := btrim(save_supplier_item.code);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_supplier_item.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) not between 1 and 100 then
    raise exception 'the code must be 1 to 100 characters' using errcode = '22023', hint = 'CATALOG_SUPPLIER_ITEM_INVALID';
  end if;
  if save_supplier_item.price is not null and save_supplier_item.price < 0 then
    raise exception 'the price can''t be negative' using errcode = '22023', hint = 'CATALOG_SUPPLIER_ITEM_INVALID';
  end if;
  if save_supplier_item.currency is not null and "better_supabase"."currency_minor_units"(save_supplier_item.currency) is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'CATALOG_CURRENCY_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."supplier_items" as x ("tenant_id", "supplier_id", "code", "description", "price", "currency", "unit", "keywords_text")
      values (save_supplier_item.tenant, save_supplier_item.supplier, v_code, save_supplier_item.description, save_supplier_item.price, save_supplier_item.currency, save_supplier_item.unit, save_supplier_item.keywords)
      returning x."id" into v_id;
    else
      update "better_supabase"."supplier_items" x set "supplier_id" = coalesce(save_supplier_item.supplier, x."supplier_id"), "code" = v_code,
        "description" = coalesce(save_supplier_item.description, x."description"), "price" = coalesce(save_supplier_item.price, x."price"),
        "currency" = coalesce(save_supplier_item.currency, x."currency"), "unit" = coalesce(save_supplier_item.unit, x."unit"),
        "keywords_text" = coalesce(save_supplier_item.keywords, x."keywords_text"), "updated_at" = now()
      where x."id" = save_supplier_item.item and x."tenant_id" = save_supplier_item.tenant;
      if not found then
        raise exception 'supplier item not found' using errcode = 'P0002', hint = 'CATALOG_SUPPLIER_ITEM_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'this supplier already has an item with this code' using errcode = '23505', hint = 'CATALOG_SUPPLIER_ITEM_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'code', v_code);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_supplier_items (
  tenant    uuid,
  query     text,
  supplier  uuid    DEFAULT NULL::uuid,
  row_limit integer DEFAULT 25
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(r.item order by r.rank desc, r.code), '[]'::jsonb)
  from (
    select x."code" as code,
      ts_rank(x."keywords", websearch_to_tsquery('simple', $2)) + case when x."code" ilike replace(replace($2, '%', ''), '_', '') || '%' then 1 else 0 end as rank,
      jsonb_build_object('id', x."id", 'supplierId', x."supplier_id", 'code', x."code", 'description', x."description", 'price', x."price", 'currency', x."currency", 'unit', x."unit", 'variantId', x."variant_id") as item
    from "better_supabase"."supplier_items" x
    where x."tenant_id" = $1 and ($3 is null or x."supplier_id" = $3)
      and (x."keywords" @@ websearch_to_tsquery('simple', $2) or x."code" ilike replace(replace($2, '%', ''), '_', '') || '%')
    order by 2 desc, 1
    limit least(greatest(coalesce($4, 25), 1), 200)
  ) r
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_location_address (
  location uuid,
  address  jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_address jsonb := set_location_address.address;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."inventory_locations" x where x."id" = set_location_address.location;
  if v_tenant is null then
    raise exception 'location not found' using errcode = 'P0002', hint = 'INVENTORY_LOCATION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'inventory.manage'), false)) then
    raise exception 'not allowed to change this inventory' using errcode = '42501', hint = 'INVENTORY_FORBIDDEN';
  end if;
  if v_address is not null and jsonb_typeof(v_address) = 'null' then
    v_address := null;
  end if;
  if v_address is not null then
    if jsonb_typeof(v_address) <> 'object'
      or exists (select 1 from jsonb_each(v_address) e where e.key <> all (array['line1', 'line2', 'postalCode', 'city', 'region', 'country']) or jsonb_typeof(e.value) <> 'string') then
      raise exception 'an address is an object of text values with the keys line1, line2, postalCode, city, region, country' using errcode = '22023', hint = 'INVENTORY_ADDRESS_INVALID';
    end if;
    if v_address ? 'country' and (v_address ->> 'country') !~ '^[A-Z]{2}$' then
      raise exception 'country is a two-letter ISO 3166 code in capitals' using errcode = '22023', hint = 'INVENTORY_ADDRESS_INVALID';
    end if;
  end if;
  update "better_supabase"."inventory_locations" x set "address" = v_address, "updated_at" = now() where x."id" = set_location_address.location;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_supplier_item_mapping (
  tenant   uuid,
  supplier uuid,
  columns  jsonb,
  defaults jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_key text;
  v_value jsonb;
  v_defaults jsonb := coalesce(set_supplier_item_mapping.defaults, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_supplier_item_mapping.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if jsonb_typeof(set_supplier_item_mapping.columns) is distinct from 'object' or jsonb_typeof(v_defaults) <> 'object' then
    raise exception 'columns and defaults must be objects' using errcode = '22023', hint = 'CATALOG_SUPPLIER_MAPPING_INVALID';
  end if;
  for v_key, v_value in select e.key, e.value from jsonb_each(set_supplier_item_mapping.columns) e loop
    if v_key <> all (array['code', 'description', 'price', 'currency', 'unit', 'keywords']) then
      raise exception 'a mapping fills only code, description, price, currency, unit, keywords' using errcode = '22023', hint = 'CATALOG_SUPPLIER_MAPPING_INVALID';
    end if;
    if not (jsonb_typeof(v_value) = 'string' or (v_key = 'keywords' and jsonb_typeof(v_value) = 'array' and not exists (select 1 from jsonb_array_elements(v_value) a where jsonb_typeof(a.value) <> 'string'))) then
      raise exception 'a mapping value is a source column name (keywords may list several)' using errcode = '22023', hint = 'CATALOG_SUPPLIER_MAPPING_INVALID';
    end if;
  end loop;
  if not (set_supplier_item_mapping.columns ? 'code') then
    raise exception 'a mapping needs a code column' using errcode = '22023', hint = 'CATALOG_SUPPLIER_MAPPING_INVALID';
  end if;
  if exists (select 1 from jsonb_object_keys(v_defaults) k where k <> all (array['currency', 'unit'])) then
    raise exception 'defaults may hold currency and unit' using errcode = '22023', hint = 'CATALOG_SUPPLIER_MAPPING_INVALID';
  end if;
  if v_defaults ? 'currency' and "better_supabase"."currency_minor_units"(v_defaults ->> 'currency') is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'CATALOG_CURRENCY_INVALID';
  end if;
  insert into "better_supabase"."supplier_item_mappings" as x ("tenant_id", "supplier_id", "columns", "defaults")
  values (set_supplier_item_mapping.tenant, set_supplier_item_mapping.supplier, set_supplier_item_mapping.columns, v_defaults)
  on conflict ("tenant_id", "supplier_id") do update set "columns" = excluded."columns", "defaults" = excluded."defaults", "updated_at" = now();
  return jsonb_build_object('supplierId', set_supplier_item_mapping.supplier, 'columns', set_supplier_item_mapping.columns, 'defaults', v_defaults);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_variant_trade_code (
  variant    uuid,
  trade_code text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_code text := nullif(replace(btrim(set_variant_trade_code.trade_code), ' ', ''), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."product_variants" x where x."id" = set_variant_trade_code.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_code is not null and v_code !~ '^[0-9]{4,10}$' then
    raise exception 'a trade code has 4 to 10 digits' using errcode = '22023', hint = 'CATALOG_TRADE_CODE_INVALID';
  end if;
  update "better_supabase"."product_variants" x set "trade_code" = v_code, "updated_at" = now() where x."id" = set_variant_trade_code.variant;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.supplier_item_from_row (
  tenant   uuid,
  supplier uuid,
  source   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_columns jsonb;
  v_defaults jsonb;
  v_code text;
  v_description text;
  v_unit text;
  v_currency text;
  v_price text;
  v_amount bigint;
  v_scale integer;
  v_keywords text;
  v_source jsonb;
begin
  select x."columns", x."defaults" into v_columns, v_defaults
  from "better_supabase"."supplier_item_mappings" x where x."tenant_id" = supplier_item_from_row.tenant and x."supplier_id" = supplier_item_from_row.supplier;
  if v_columns is null then
    raise exception 'this supplier has no column mapping' using errcode = 'P0002', hint = 'CATALOG_SUPPLIER_MAPPING_NOT_FOUND';
  end if;
  if jsonb_typeof(supplier_item_from_row.source) is distinct from 'object' then
    raise exception 'a row is an object of source columns' using errcode = '22023', hint = 'CATALOG_SUPPLIER_ROW_INVALID';
  end if;
  v_code := nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'code')), '');
  v_description := nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'description')), '');
  v_unit := coalesce(nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'unit')), ''), v_defaults ->> 'unit');
  v_currency := upper(coalesce(nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'currency')), ''), v_defaults ->> 'currency'));
  v_price := nullif(btrim(supplier_item_from_row.source ->> (v_columns ->> 'price')), '');
  if v_currency is not null and "better_supabase"."currency_minor_units"(v_currency) is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'CATALOG_CURRENCY_INVALID';
  end if;
  if v_price is not null then
    v_price := regexp_replace(v_price, '[^0-9.,-]', '', 'g');
    if position(',' in v_price) > 0 and position('.' in v_price) > 0 then
      -- The separator that comes last is the decimal one.
      if length(v_price) - length(regexp_replace(v_price, '^.*,', '')) > length(v_price) - length(regexp_replace(v_price, '^.*\.', '')) then
        v_price := replace(replace(v_price, '.', ''), ',', '.');
      else
        v_price := replace(v_price, ',', '');
      end if;
    else
      v_price := replace(v_price, ',', '.');
    end if;
    v_scale := coalesce("better_supabase"."currency_minor_units"(v_currency), 2);
    begin
      v_amount := round(v_price::numeric * power(10::numeric, v_scale))::bigint;
    exception when others then
      raise exception 'the price is not a number' using errcode = '22023', hint = 'CATALOG_SUPPLIER_PRICE_INVALID';
    end;
    if v_amount < 0 then
      raise exception 'the price can''t be negative' using errcode = '22023', hint = 'CATALOG_SUPPLIER_PRICE_INVALID';
    end if;
  end if;
  v_source := case jsonb_typeof(v_columns -> 'keywords') when 'array' then v_columns -> 'keywords' when 'string' then jsonb_build_array(v_columns -> 'keywords') else '[]'::jsonb end;
  select nullif(string_agg(btrim(supplier_item_from_row.source ->> (a.value #>> '{}')), ' ') filter (where nullif(btrim(supplier_item_from_row.source ->> (a.value #>> '{}')), '') is not null), '')
  into v_keywords from jsonb_array_elements(v_source) a;
  return jsonb_strip_nulls(jsonb_build_object('code', v_code, 'description', v_description, 'price', v_amount, 'currency', v_currency, 'unit', v_unit, 'keywords', v_keywords));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.supplier_item_mapping (
  tenant   uuid,
  supplier uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('supplierId', x."supplier_id", 'columns', x."columns", 'defaults', x."defaults")
  from "better_supabase"."supplier_item_mappings" x where x."tenant_id" = $1 and x."supplier_id" = $2
$function$;

CREATE OR REPLACE FUNCTION better_supabase.supplier_item_updated_at (
  subject_id text
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."updated_at" from "better_supabase"."supplier_items" x where x."id" = $1::uuid
$function$;

CREATE OR REPLACE FUNCTION better_supabase.variant_identifiers (
  variant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'type', x."type", 'value', x."value", 'partyId', x."party_id") order by x."type", x."value"), '[]'::jsonb)
  from "better_supabase"."product_identifiers" x where x."variant_id" = $1
$function$;

CREATE OR REPLACE FUNCTION better_supabase.variant_relations (
  variant uuid,
  kind    text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('kind', q.kind, 'direction', q.direction, 'variantId', q.other, 'sku', y."sku") order by q.kind, q.direction, y."sku"), '[]'::jsonb)
  from (
    select x."kind" as kind, 'outgoing' as direction, x."to_variant_id" as other from "better_supabase"."product_relations" x where x."from_variant_id" = $1
    union all
    select x."kind", 'incoming', x."from_variant_id" from "better_supabase"."product_relations" x where x."to_variant_id" = $1
  ) q
  join "better_supabase"."product_variants" y on y."id" = q.other
  where $2 is null or q.kind = $2
$function$;

ALTER TABLE "better_supabase"."inventory_locations"
  ADD CONSTRAINT "inventory_locations_address_check" CHECK (((address IS NULL) OR (jsonb_typeof(address) = 'object'::text)));

ALTER TABLE "better_supabase"."product_identifiers"
  ADD CONSTRAINT "product_identifiers_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."product_relations"
  ADD CONSTRAINT "product_relations_from_variant_id_fkey" FOREIGN KEY (from_variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."product_relations"
  ADD CONSTRAINT "product_relations_to_variant_id_fkey" FOREIGN KEY (to_variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."product_variants"
  ADD CONSTRAINT "product_variants_trade_code_check" CHECK ((trade_code ~ '^[0-9]{4,10}$'::text));

ALTER TABLE "better_supabase"."supplier_items"
  ADD CONSTRAINT "supplier_items_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES better_supabase.product_variants(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX product_identifiers_key ON better_supabase.product_identifiers
  USING btree (variant_id, TYPE, VALUE, COALESCE(party_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX product_identifiers_lookup_idx ON better_supabase.product_identifiers USING btree (tenant_id, TYPE, VALUE);

CREATE INDEX product_relations_to_idx ON better_supabase.product_relations USING btree (to_variant_id, kind);

CREATE INDEX supplier_items_keywords_idx ON better_supabase.supplier_items USING gin (keywords);

CREATE INDEX supplier_items_variant_idx ON better_supabase.supplier_items USING btree (variant_id);

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."product_identifiers"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."product_identifiers"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."product_identifiers"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."product_identifiers"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "product_identifiers_read" ON "better_supabase"."product_identifiers"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."product_relations"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."product_relations"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."product_relations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."product_relations"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "product_relations_read" ON "better_supabase"."product_relations"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."supplier_item_mappings"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."supplier_item_mappings"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."supplier_item_mappings"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."supplier_item_mappings"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "supplier_item_mappings_read" ON "better_supabase"."supplier_item_mappings"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

CREATE POLICY "bsb_tenant_scope_delete" ON "better_supabase"."supplier_items"
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_insert" ON "better_supabase"."supplier_items"
  AS RESTRICTIVE
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."supplier_items"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text)
    AS tenant_ids_with))));

CREATE POLICY "bsb_tenant_scope_update" ON "better_supabase"."supplier_items"
  AS RESTRICTIVE
  FOR UPDATE
  TO PUBLIC
  USING ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "supplier_items_read" ON "better_supabase"."supplier_items"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)));

REVOKE ALL ON FUNCTION "api"."delete_product_identifier"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_product_identifier"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_product_relation"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_product_relation"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_supplier_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_supplier_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_supplier_item_mapping"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_supplier_item_mapping"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."find_variants_by_identifier"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."find_variants_by_identifier"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."import_product_identifier"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_product_identifier"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."import_supplier_item"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_supplier_item"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."product_identifier_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."product_identifier_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."promote_supplier_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."promote_supplier_item"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."replacement_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."replacement_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_product_identifier"(uuid, uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_product_identifier"(uuid, uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_product_relation"(uuid, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_product_relation"(uuid, uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_supplier_item"(uuid, uuid, uuid, text, text, bigint, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_supplier_item"(uuid, uuid, uuid, text, text, bigint, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."search_supplier_items"(uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."search_supplier_items"(uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_location_address"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_location_address"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_supplier_item_mapping"(uuid, uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_supplier_item_mapping"(uuid, uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_variant_trade_code"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_variant_trade_code"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."supplier_item_from_row"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."supplier_item_from_row"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."supplier_item_mapping"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."supplier_item_mapping"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."supplier_item_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."supplier_item_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."variant_identifiers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."variant_identifiers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."variant_relations"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."variant_relations"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_product_identifier"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_product_identifier"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_product_relation"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_product_relation"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_supplier_item"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_supplier_item"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_supplier_item_mapping"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_supplier_item_mapping"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."find_variants_by_identifier"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."find_variants_by_identifier"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_product_identifier"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_product_identifier"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_supplier_item"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_supplier_item"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."product_identifier_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."product_identifier_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."promote_supplier_item"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."promote_supplier_item"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."replacement_variant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."replacement_variant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_product_identifier"(uuid, uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_product_identifier"(uuid, uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_product_relation"(uuid, uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_product_relation"(uuid, uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_supplier_item"(uuid, uuid, uuid, text, text, bigint, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_supplier_item"(uuid, uuid, uuid, text, text, bigint, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."search_supplier_items"(uuid, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."search_supplier_items"(uuid, text, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_location_address"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_location_address"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_supplier_item_mapping"(uuid, uuid, jsonb, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_supplier_item_mapping"(uuid, uuid, jsonb, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_variant_trade_code"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_variant_trade_code"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."supplier_item_from_row"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."supplier_item_from_row"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."supplier_item_mapping"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."supplier_item_mapping"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."supplier_item_updated_at"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."supplier_item_updated_at"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."variant_identifiers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."variant_identifiers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."variant_relations"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."variant_relations"(uuid, text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."product_identifiers" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."product_identifiers" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."product_relations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."product_relations" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."supplier_item_mappings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."supplier_item_mappings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."supplier_items" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."supplier_items" TO "service_role";
