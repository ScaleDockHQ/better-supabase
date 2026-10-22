SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."message_record_mentions" (
  "tenant_id"       uuid                     NOT NULL,
  "message_id"      uuid                     NOT NULL,
  "conversation_id" uuid                     NOT NULL,
  "subject_type"    text                     NOT NULL,
  "subject_id"      text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "message_record_mentions_pkey" PRIMARY KEY (message_id, subject_type, subject_id)
);

ALTER TABLE "better_supabase"."message_record_mentions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.list_record_mentions (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id    uuid                     DEFAULT NULL::uuid,
  max_rows     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_record_mentions"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.subject_presence_allowed (
  topic text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."subject_presence_allowed"($1) $function$;

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
    ('organization', 'better_supabase.message_record_mentions', '"better_supabase"."message_record_mentions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.channels', '"better_supabase"."channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_message (
  message uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = delete_message.message and m."deleted_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_msg."author_id" = auth.uid() or "better_supabase"."can_conversation"(v_msg."conversation_id", 'moderate')) then
    raise exception 'not allowed to delete this message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  update "better_supabase"."messages" m set "body" = '', "document" = null, "mentions" = '{}', "mention_scope" = null,
    "pinned_at" = null, "pinned_by" = null, "deleted_at" = now()
  where m."id" = v_msg."id"
  returning * into v_msg;
  delete from "better_supabase"."message_edits" x where x."message_id" = v_msg."id";
  delete from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id";
  delete from "better_supabase"."attachments" a
  where a."subject_type" = 'message' and a."subject_id" = v_msg."id"::text;
  if v_msg."sent_at" is not null then
    perform "better_supabase".emit_event('message.deleted', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_inbox_message (
  message uuid,
  body    text    DEFAULT NULL::text,
  remove  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_msg "better_supabase"."messages"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m.* into v_msg from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = edit_inbox_message.message
  for update of m;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_msg."author_id" is not null and v_msg."author_id" = (select auth.uid()))) then
    raise exception 'only the author edits a message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if v_msg."deleted_at" is not null then
    raise exception 'message is deleted' using errcode = '22023', hint = 'MESSAGE_DELETED';
  end if;
  if length(coalesce(edit_inbox_message.body, '')) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  update "better_supabase"."messages" set
    "body" = case when coalesce(remove, false) then '' else coalesce(edit_inbox_message.body, "body") end,
    "deleted_at" = case when coalesce(remove, false) then now() end,
    "edited_at" = case when coalesce(remove, false) then "edited_at" else now() end
  where "id" = v_msg."id";
  perform "better_supabase"."index_record_mentions"(v_msg."id");
  if coalesce(remove, false) then
    delete from "better_supabase"."attachments" x where x."subject_type" = 'message' and x."subject_id" = v_msg."id"::text;
  end if;
  return "better_supabase"."inbox_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_message (
  message uuid,
  body    text,
  attrs   jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
  v_parsed jsonb := "better_supabase"."parse_mentions"(edit_message.body);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_msg from "better_supabase"."messages" m
  where m."id" = edit_message.message and m."author_id" = auth.uid() and m."deleted_at" is null
    and "better_supabase"."can_conversation"(m."conversation_id", 'read');
  if not found then
    raise exception 'no message of yours has this id' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_msg."sent_at" is not null and not (true) then
    raise exception 'this message can no longer be edited' using errcode = '55000', hint = 'MESSAGING_EDIT_CLOSED';
  end if;
  if nullif(trim(coalesce(edit_message.body, '')), '') is null then
    raise exception 'a message needs a body' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_edit"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using edit_message.message, edit_message.body;
    end if;
  end;
  insert into "better_supabase"."message_edits" ("tenant_id", "message_id", "body", "document", "edited_by")
  values (v_msg."tenant_id", v_msg."id", v_msg."body", v_msg."document", auth.uid());
  begin
    update "better_supabase"."messages" m set
      "body" = edit_message.body,
      "document" = case when edit_message.attrs ? 'document' then edit_message.attrs -> 'document' else m."document" end,
      "mentions" = array(
        select distinct x from (
          select (jsonb_array_elements_text(coalesce(edit_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
          union
          select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
        ) s
      ),
      "edited_at" = now()
    where m."id" = v_msg."id"
    returning * into v_msg;
  exception when check_violation or invalid_text_representation then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  if v_msg."sent_at" is not null then
    perform "better_supabase"."index_record_mentions"(v_msg."id");
    perform "better_supabase".emit_event('message.edited', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text)
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_edit"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
  return "better_supabase"."messaging_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_add_message (
  conversation uuid,
  input        jsonb,
  author_type  text,
  author       uuid,
  direction    text
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_id uuid;
  v_at timestamptz := clock_timestamp();
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_body text := coalesce(input ->> 'body', '');
  v_mentions uuid[];
  v_uploads uuid[];
  v_file jsonb;
  v_moved integer;
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select d."message_id" into v_id from "better_supabase"."inbox_message_details" d
    where d."conversation_id" = v_conv."id" and d."external_id" = input ->> 'external_id';
    if found then
      return v_id;
    end if;
  end if;
  if v_kind not in ('message', 'note') then
    raise exception 'kind is message or note' using errcode = '22023', hint = 'INBOX_KIND_INVALID';
  end if;
  v_uploads := array(select distinct x::uuid from jsonb_array_elements_text(coalesce(input -> 'attachments', '[]'::jsonb)) x);
  if length(btrim(v_body)) = 0 and cardinality(v_uploads) = 0 and coalesce(jsonb_array_length(input -> 'files'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  if length(v_body) > 20000 then
    raise exception 'a message is at most 20000 characters' using errcode = '22023', hint = 'INBOX_MESSAGE_TOO_LONG';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "author_id", "kind", "body", "mentions", "sent_at", "created_at")
  values (v_conv."tenant_id", v_conv."id", inbox_add_message.author, v_kind, v_body, v_mentions, v_at, v_at)
  returning "id" into v_id;
  perform "better_supabase"."index_record_mentions"(v_id);
  insert into "better_supabase"."inbox_message_details" ("message_id", "tenant_id", "conversation_id", "direction", "author_type", "format", "external_id", "reply_to", "metadata")
  values (
    v_id, v_conv."tenant_id", v_conv."id", inbox_add_message.direction, inbox_add_message.author_type,
    coalesce(input ->> 'format', 'text'), input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  );
  if cardinality(v_uploads) > 0 then
    update "better_supabase"."attachments" x set "subject_type" = 'message', "subject_id" = v_id::text
    where x."id" = any (v_uploads)
      and x."organization_id" = v_conv."tenant_id"
      and x."subject_type" = 'conversation' and x."subject_id" = v_conv."id"::text
      and x."status" <> 'infected'
      and (inbox_add_message.author is null or x."uploaded_by" = inbox_add_message.author);
    get diagnostics v_moved = row_count;
    if v_moved <> cardinality(v_uploads) then
      raise exception 'attachments must be your uploads to this conversation' using errcode = '22023', hint = 'INBOX_ATTACHMENT_INVALID';
    end if;
  end if;
  for v_file in select f from jsonb_array_elements(coalesce(input -> 'files', '[]'::jsonb)) f loop
    insert into "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id", "name", "mime_type", "size", "uploaded_by", "scan_detail")
    values (
      v_conv."tenant_id", 'message', v_id::text,
      left(coalesce(nullif(v_file ->> 'name', ''), 'file'), 255),
      lower(coalesce(nullif(v_file ->> 'content_type', ''), 'application/octet-stream')),
      coalesce((v_file ->> 'size')::bigint, 0),
      null,
      jsonb_build_object('source', v_file)::text
    );
  end loop;
  if inbox_add_message.author is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."inbox_conversations" set
      "last_message_at" = v_at,
      "last_message_preview" = left(v_body, 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_at
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snoozed_until" = case when v_reopened then null else "snoozed_until" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      perform "better_supabase".emit_event('inbox_conversation.reopened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    end if;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    perform "better_supabase".emit_event('inbox_message.received', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'messageId', v_id, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, 'inbox_message.received:' || v_id::text, 'better-supabase/inbox');
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_bot', payload => jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_id, 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox:' || v_conv."id"::text, dedupe_running => false);
    end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_conv."tenant_id", v_id, v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"(queue => 'inbox_outbound', payload => jsonb_build_object('message_id', v_id, 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), dedupe_key => 'inbox-out:' || v_id::text, dedupe_running => false);
    end if;
  end if;
  if cardinality(v_mentions) > 0 then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.mention',
      'tenant', v_conv."tenant_id",
      'actor', inbox_add_message.author,
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_body, 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_id::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_id)
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.index_record_mentions (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."message_record_mentions" x where x."message_id" = index_record_mentions.message;
  insert into "better_supabase"."message_record_mentions" ("tenant_id", "message_id", "conversation_id", "subject_type", "subject_id", "created_at")
  select m."tenant_id", m."id", m."conversation_id", r.subject_type, r.subject_id, m."sent_at"
  from "better_supabase"."messages" m
  cross join lateral (
    select s ->> 'type' as subject_type, s ->> 'id' as subject_id
    from jsonb_array_elements("better_supabase"."parse_mentions"(m."body") -> 'subjects') s
    where s ->> 'type' = any ("better_supabase"."subject_types"())
    limit 20
  ) r
  where m."id" = index_record_mentions.message
    and m."sent_at" is not null and m."deleted_at" is null
  on conflict do nothing;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_record_mentions (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  before_id    uuid                     DEFAULT NULL::uuid,
  max_rows     integer                  DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select case when not coalesce("better_supabase"."can_subject"(list_record_mentions.subject_type, list_record_mentions.subject_id, 'read'), false)
    then '[]'::jsonb
    else coalesce((
      select jsonb_agg(jsonb_build_object(
        'message', "better_supabase"."messaging_messages_json"(array[p.message]) -> 0,
        'conversation', jsonb_build_object('id', c."id", 'kind', c."kind", 'title', c."title", 'subject_type', c."subject_type", 'subject_id', c."subject_id")
      ) order by p.created_at desc, p.message desc)
      from (
        select x."message_id" as message, x."conversation_id" as conversation, x."created_at" as created_at
        from "better_supabase"."message_record_mentions" x
        where x."subject_type" = list_record_mentions.subject_type and x."subject_id" = list_record_mentions.subject_id
          and (list_record_mentions.before is null
            or (x."created_at", x."message_id") < (list_record_mentions.before, coalesce(list_record_mentions.before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
        order by x."created_at" desc, x."message_id" desc
        limit least(greatest(coalesce(list_record_mentions.max_rows, 20), 1), 100)
      ) p
      join "better_supabase"."conversations" c on c."id" = p.conversation
    ), '[]'::jsonb)
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_sent (
  message uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages";
  v_conv "better_supabase"."conversations";
  v_mentioned uuid[];
  v_direct uuid[];
  v_claims text;
begin
  select * into v_msg from "better_supabase"."messages" m where m."id" = messaging_message_sent.message;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id";
  perform "better_supabase"."index_record_mentions"(v_msg."id");
  perform "better_supabase".emit_event('message.sent', jsonb_build_object('organizationId', v_msg."tenant_id"::text, 'conversationId', v_msg."conversation_id", 'messageId', v_msg."id", 'authorId', v_msg."author_id", 'threadId', v_msg."thread_id", 'subjectType', 'message', 'subjectId', v_msg."id"::text, 'mentionIds', to_jsonb(v_msg."mentions"), 'recordMentions', (select coalesce(jsonb_agg(jsonb_build_object('type', x."subject_type", 'id', x."subject_id") order by x."subject_type", x."subject_id"), '[]'::jsonb) from "better_supabase"."message_record_mentions" x where x."message_id" = v_msg."id"))
      || coalesce((select jsonb_build_object('conversationKind', c."kind", 'recordType', c."subject_type", 'recordId', c."subject_id") from "better_supabase"."conversations" c where c."id" = v_msg."conversation_id"), '{}'::jsonb), 'messages/' || v_msg."id"::text, (v_msg."tenant_id"::text)::text, null, 'better-supabase/messaging');
  -- Mentioned users who can read the conversation.
  v_mentioned := array(
    select distinct x from unnest(v_msg."mentions") x
    where x is distinct from v_msg."author_id"
      and coalesce(better_supabase.can_user(x, 'tenant', v_msg."tenant_id", 'messages.read'), false)
        and (v_conv."access" <> 'members' or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = x))
        and (v_conv."access" <> 'subject' or case v_conv."subject_type" when 'message' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'conversation' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'channel' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'company' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'person' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'deal' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'engagement' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'work_item' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'employee' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'product_variant' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'calendar_event' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'document' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'customer' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'drive_node' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) when 'application' then coalesce("better_supabase"."can_subject_for"(x, v_conv."subject_type", v_conv."subject_id", 'read'), false) else true end)
  );
  if v_msg."mention_scope" is not null then
    v_mentioned := v_mentioned || array(
      select k."user_id" from "better_supabase"."conversation_members" k
      where k."conversation_id" = v_conv."id" and k."notify" <> 'none'
        and k."user_id" is distinct from v_msg."author_id"
    );
  end if;
  v_mentioned := array(
    select distinct x from unnest(v_mentioned) x
    where not exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = x and k."notify" = 'none')
  );
  if cardinality(v_mentioned) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.mentioned',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', to_jsonb(v_mentioned),
      'watchers', false,
      'key', 'message.mentioned:' || v_msg."id"::text
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if v_conv."kind" in ('dm', 'group_dm') and v_msg."thread_id" is null then
    v_direct := array(
      select k."user_id" from "better_supabase"."conversation_members" k
      where k."conversation_id" = v_conv."id" and k."notify" = 'all'
        and k."user_id" is distinct from v_msg."author_id"
        and not k."user_id" = any (v_mentioned)
    );
    if cardinality(v_direct) > 0 then
      v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.direct',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', to_jsonb(v_direct),
      'watchers', false,
      'key', 'message.direct:' || v_msg."id"::text
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if v_msg."thread_id" is not null then
    -- The replier and the root's author follow the thread; its followers
    -- hear of the reply, less the members already told above.
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", v_msg."author_id", 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_msg."tenant_id", (select r."author_id" from "better_supabase"."messages" r where r."id" = v_msg."thread_id"), 'message', v_msg."thread_id"::text, 'participating')
    on conflict do nothing;
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'message.replied',
      'tenant', v_msg."tenant_id",
      'actor', v_msg."author_id",
      'subject_type', 'message',
      'subject_id', coalesce(v_msg."thread_id", v_msg."id")::text,
      'summary', left(v_msg."body", 140),
      'data', jsonb_build_object('messageId', v_msg."id", 'conversationId', v_msg."conversation_id"),
      'recipients', '[]'::jsonb,
      'exclude', to_jsonb(v_mentioned),
      'key', 'message.replied:' || v_msg."id"::text
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_message_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_msg."id";
    end if;
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_presence_allowed (
  topic text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_parts text[] := regexp_match(subject_presence_allowed.topic, '^presence:([a-z][a-z0-9_]{0,62}):([^:]{1,200})$');
begin
  if v_parts is null then
    return false;
  end if;
  return coalesce("better_supabase"."can_subject"(v_parts[1], v_parts[2], 'read'), false);
exception
  when invalid_text_representation then
    return false;
end;
$function$;

ALTER TABLE "better_supabase"."message_record_mentions"
  ADD CONSTRAINT "message_record_mentions_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES better_supabase.conversations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."message_record_mentions"
  ADD CONSTRAINT "message_record_mentions_message_id_fkey" FOREIGN KEY (message_id) REFERENCES better_supabase.messages(id) ON DELETE CASCADE;

CREATE INDEX messaging_record_mentions_conversation_idx ON better_supabase.message_record_mentions USING btree (conversation_id);

CREATE INDEX messaging_record_mentions_subject_idx ON better_supabase.message_record_mentions USING btree (subject_type, subject_id, created_at DESC, message_id);

CREATE POLICY "message_record_mentions_read" ON "better_supabase"."message_record_mentions"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.messages m
  WHERE (m.id = message_record_mentions.message_id))));

CREATE POLICY "bs_subject_presence_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'presence'::text) AND (( SELECT realtime.topic() AS topic) ~~ ('presence:'::text || '%'::text)) AND better_supabase.subject_presence_allowed(( SELECT
    realtime.topic() AS topic))));

CREATE POLICY "bs_subject_presence_send" ON "realtime"."messages"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((extension = 'presence'::text) AND (( SELECT realtime.topic() AS topic) ~~ ('presence:'::text || '%'::text)) AND better_supabase.subject_presence_allowed(( SELECT
    realtime.topic() AS topic)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

REVOKE ALL ON FUNCTION "api"."list_record_mentions"(text, text, timestamp WITH time zone, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_record_mentions"(text, text, timestamp WITH time zone, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."subject_presence_allowed"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."subject_presence_allowed"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."index_record_mentions"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."list_record_mentions"(text, text, timestamp WITH time zone, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_record_mentions"(text, text, timestamp WITH time zone, uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."subject_presence_allowed"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."subject_presence_allowed"(text) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."message_record_mentions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."message_record_mentions" TO "service_role";
