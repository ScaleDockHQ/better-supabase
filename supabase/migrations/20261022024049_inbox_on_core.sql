SET local check_function_bodies = off;

DROP POLICY "conversations_read" ON "better_supabase"."conversations";

DROP POLICY "messages_read" ON "better_supabase"."messages";

DROP POLICY "reactions_delete" ON "better_supabase"."reactions";

DROP POLICY "reactions_insert" ON "better_supabase"."reactions";

DROP POLICY "bs_inbox_broadcast" ON "realtime"."messages";

DROP POLICY "bs_inbox_receive" ON "realtime"."messages";

DROP FUNCTION "api"."inbox_contact_read_at"(uuid);

DROP FUNCTION "api"."react_to_message"(uuid, text, boolean, text);

DROP FUNCTION "api"."set_inbox_typing"(uuid, boolean, text);

DROP FUNCTION "api"."set_typing"(uuid, boolean);

DROP FUNCTION "better_supabase"."inbox_contact_read_at"(uuid);

DROP FUNCTION "better_supabase"."inbox_conversation_json"(uuid);

DROP FUNCTION "better_supabase"."inbox_counts"(uuid);

DROP FUNCTION "better_supabase"."list_inbox_conversations"(uuid, jsonb);

DROP FUNCTION "better_supabase"."list_inbox_messages"(uuid, timestamp WITH time zone, integer);

DROP FUNCTION "better_supabase"."set_typing"(uuid, boolean);

ALTER TABLE "better_supabase"."inbox_message_details"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.create_inbox_attachment (
  conversation uuid,
  name         text,
  mime_type    text,
  size         bigint
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_inbox_attachment"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.inbox_file_failed (
  attachment uuid,
  detail     text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."inbox_file_failed"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.pending_inbox_files (
  max integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_inbox_files"($1) $function$;

CREATE OR REPLACE FUNCTION api.react_to_inbox_message (
  message uuid,
  emoji   text,
  present boolean DEFAULT true,
  actor   text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."react_to_inbox_message"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_typing (
  conversation uuid,
  typing       boolean DEFAULT true,
  actor        text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_typing"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.assign_conversation (
  conversation uuid,
  assignee     uuid,
  team         uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = assign_conversation.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.assign'), false) or (assignee = (select auth.uid()) and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false))) then
    raise exception 'not allowed to assign this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if assignee is not null and not coalesce(better_supabase.can_user(assignee, 'tenant', v_conv."tenant_id", 'inbox.read'), false) then
    raise exception 'the assignee cannot read this inbox' using errcode = '22023', hint = 'INBOX_ASSIGNEE_INVALID';
  end if;
  v_before := v_conv."assignee_id";
  update "better_supabase"."inbox_conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    perform "better_supabase".emit_event('inbox_conversation.assigned', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status", 'previousAssigneeId', v_before), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
    if assignee is not null then
      insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_conv."id", v_conv."tenant_id", assign_conversation.assignee)
    on conflict do nothing;
    end if;
    if assignee is not null and assignee is distinct from (select auth.uid()) then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.assigned',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', v_conv."subject",
        'recipients', to_jsonb(array[assignee]),
        'key', 'inbox.assigned:' || v_conv."id"::text || ':' || assignee::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id")
      ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_conversation (
  conversation uuid,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations";
begin
  select * into v_conv from "better_supabase"."conversations" c
  where c."id" = can_conversation.conversation
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end) end));
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  if v_conv."kind" = 'inbox' then
    return "better_supabase"."inbox_can_conversation"(v_conv."id", can_conversation.action);
  end if;
  case can_conversation.action
    when 'read' then
      return true;
    when 'send' then
      return v_conv."archived_at" is null
        and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.send'), false)
        and (v_conv."access" <> 'members' or "better_supabase"."is_conversation_member"(v_conv."id"));
    when 'moderate' then
      return coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.moderate'), false);
    else
      return false;
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_inbox_attachment (
  conversation uuid,
  name         text,
  mime_type    text,
  size         bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_row "better_supabase"."attachments"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" v where v."id" = create_inbox_attachment.conversation;
  if not found or (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(v_conv."id"::text, true) then
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."attachments" ("organization_id", "subject_type", "subject_id", "name", "mime_type", "size", "uploaded_by")
  values (v_conv."tenant_id", 'conversation', v_conv."id"::text, create_inbox_attachment.name, lower(create_inbox_attachment.mime_type), create_inbox_attachment.size, (select auth.uid()))
  returning * into v_row;
  return to_jsonb(v_row);
exception when check_violation then
  raise exception 'the file''s name, type or size is not allowed' using errcode = '22023', hint = 'INBOX_ATTACHMENT_INVALID';
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
    ('organization', 'better_supabase.activity_entries', '"better_supabase"."activity_entries"', 'organization_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
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
  if coalesce(remove, false) then
    delete from "better_supabase"."attachments" x where x."subject_type" = 'message' and x."subject_id" = v_msg."id"::text;
  end if;
  return "better_supabase"."inbox_messages_json"(array[v_msg."id"]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_inbox_message (
  message uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."inbox_messages_json"(array[get_inbox_message.message]) -> 0;
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

CREATE OR REPLACE FUNCTION better_supabase.inbox_can_conversation (
  conversation uuid,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case inbox_can_conversation.action
    when 'read' then
      return "better_supabase"."inbox_conversation_allowed"(inbox_can_conversation.conversation::text);
    when 'send' then
      return "better_supabase"."inbox_conversation_allowed"(inbox_can_conversation.conversation::text, true);
    when 'moderate' then
      return exists (
        select 1 from "better_supabase"."inbox_conversations" v
        where v."id" = inbox_can_conversation.conversation and coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.manage'), false)
      );
    else
      return false;
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_contact_read_at (
  conversation uuid
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return (
    select k."last_read_at"
    from "better_supabase"."inbox_conversations" v
    join "better_supabase"."contacts" c on c."id" = v."contact_id"
    join "better_supabase"."conversation_members" k on k."conversation_id" = v."id" and k."user_id" = c."user_id"
    where v."id" = inbox_contact_read_at.conversation
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_conversation_allowed (
  conversation text,
  write        boolean DEFAULT false
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce((
    select (case when write then coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.reply'), false) else coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false) end)
      or exists (select 1 from "better_supabase"."contacts" c where c."id" = v."contact_id" and c."user_id" = (select auth.uid()))
    from "better_supabase"."inbox_conversations" v
    where v."id"::text = conversation
  ), false);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_conversation_broadcast()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_payload jsonb := jsonb_build_object('conversation_id', new."id");
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(v_payload, 'conversation', 'messages:' || new."id"::text, true);
    perform realtime.send(v_payload, 'conversation', 'inbox:org:' || new."tenant_id"::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_conversation_json (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    select to_jsonb(v) || jsonb_build_object(
      'contact', (select jsonb_build_object('id', c."id", 'name', c."name", 'email', c."email", 'phone', c."phone", 'avatar_url', c."avatar_url", 'user_id', c."user_id") from "better_supabase"."contacts" c where c."id" = v."contact_id"),
      'inbox', (select jsonb_build_object('id', i."id", 'name', i."name", 'channel', i."channel") from "better_supabase"."inboxes" i where i."id" = v."inbox_id"),
      'last_read_at', (select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = v."id" and k."user_id" = (select auth.uid())),
      'contact_read_at', "better_supabase"."inbox_contact_read_at"(v."id")
    )
    from "better_supabase"."inbox_conversations" v
    where v."id" = inbox_conversation_json.conversation
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    select jsonb_build_object(
      'open', count(*),
      'mine', count(*) filter (where v."assignee_id" = (select auth.uid())),
      'unassigned', count(*) filter (where v."assignee_id" is null),
      'unread', count(*) filter (where v."last_message_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
        and (v."assignee_id" is null or v."assignee_id" = (select auth.uid())))
    )
    from "better_supabase"."inbox_conversations" v
    left join "better_supabase"."conversation_members" k on k."conversation_id" = v."id" and k."user_id" = (select auth.uid())
    where v."tenant_id" = inbox_counts.tenant and v."status" = 'open'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_delivery_broadcast()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('conversation_id', d."conversation_id", 'message_id', new."message_id", 'status', new."status"),
      'delivery',
      'inbox:org:' || new."tenant_id"::text,
      true
    )
    from "better_supabase"."inbox_message_details" d where d."message_id" = new."message_id";
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_file_allowed (
  bucket      text,
  object_name text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return exists (
    select 1 from "better_supabase"."attachments" a
    join "better_supabase"."messages" m on a."subject_type" = 'message' and m."id"::text = a."subject_id"
    join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
    where a."bucket" = inbox_file_allowed.bucket and a."object_path" = inbox_file_allowed.object_name
      and a."status" = 'clean'
      and m."deleted_at" is null
      and "better_supabase"."inbox_conversation_allowed"(d."conversation_id"::text)
      and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(d."conversation_id"))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_file_failed (
  attachment uuid,
  detail     text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."attachments" x set
    "status" = 'failed',
    "scan_detail" = coalesce(inbox_file_failed.detail, 'import failed'),
    "scanned_at" = now()
  where x."id" = inbox_file_failed.attachment and x."status" = 'pending' and x."uploaded_at" is null;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_message_broadcast()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
begin
  if not to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null or new."sent_at" is null then
    return null;
  end if;
  select v."tenant_id"::text into v_tenant from "better_supabase"."inbox_conversations" v where v."id" = new."conversation_id";
  if v_tenant is not null then
    perform realtime.send(jsonb_build_object('conversation_id', new."conversation_id", 'message_id', new."id", 'kind', new."kind"), case when tg_op = 'INSERT' or old."sent_at" is null then 'message' else 'message_updated' end, 'inbox:org:' || v_tenant::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_messages_json (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_ids uuid[];
begin
  select array_agg(m."id") into v_ids
  from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = any (inbox_messages_json.ids)
    and m."sent_at" is not null
    and "better_supabase"."inbox_conversation_allowed"(d."conversation_id"::text)
    and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(d."conversation_id"));
  if v_ids is null then
    return '[]'::jsonb;
  end if;
  return (
    select coalesce(jsonb_agg(x.item || to_jsonb(d) || jsonb_build_object('delivery', case when "better_supabase"."inbox_note_readable"(d."conversation_id") then (
      select jsonb_build_object('status', l."status", 'channel', l."channel", 'error', l."error", 'updated_at', l."updated_at")
      from "better_supabase"."message_deliveries" l where l."message_id" = d."message_id"
      order by l."created_at" limit 1
    ) end) order by x.n), '[]'::jsonb)
    from jsonb_array_elements("better_supabase"."messaging_messages_json"(v_ids)) with ordinality as x (item, n)
    join "better_supabase"."inbox_message_details" d on d."message_id" = (x.item ->> 'id')::uuid
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_note_readable (
  conversation uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or exists (
    select 1 from "better_supabase"."inbox_conversations" v
    where v."id" = inbox_note_readable.conversation and coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false)
  );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_conversations (
  tenant   uuid,
  kinds    text[]  DEFAULT NULL::text[],
  max_rows integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(
    to_jsonb(c) || jsonb_build_object(
      'unread', u.unread,
      'mentions', u.mentions,
      'lastReadAt', k."last_read_at",
      'notify', k."notify"
    ) order by c."last_message_at" desc nulls last, c."id"), '[]'::jsonb)
  from (
    select c.* from "better_supabase"."conversations" c
    join "better_supabase"."conversation_members" k on k."conversation_id" = c."id" and k."user_id" = auth.uid()
    where c."tenant_id" = list_conversations.tenant
      and (list_conversations.kinds is null and c."kind" <> 'inbox' or c."kind" = any (list_conversations.kinds))
    order by c."last_message_at" desc nulls last, c."id"
    limit least(greatest(coalesce(list_conversations.max_rows, 100), 1), 500)
  ) c
  join "better_supabase"."conversation_members" k on k."conversation_id" = c."id" and k."user_id" = auth.uid()
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) as mentions
    from "better_supabase"."messages" m
    where m."conversation_id" = c."id"
      and (m."thread_id" is null or m."broadcast")
      and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
      and m."deleted_at" is null
      and m."author_id" is distinct from auth.uid()
  ) u
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_inbox_conversations (
  tenant uuid  DEFAULT NULL::uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
    select coalesce(jsonb_agg("better_supabase"."inbox_conversation_json"(page."id") || jsonb_build_object('unread', page.unread) order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
    from (
      select v."id", v."last_message_at",
        v."last_message_at" > coalesce((select k."last_read_at" from "better_supabase"."conversation_members" k where k."conversation_id" = v."id" and k."user_id" = (select auth.uid())), '-infinity'::timestamptz) as unread
      from "better_supabase"."inbox_conversations" v
      left join "better_supabase"."contacts" c on c."id" = v."contact_id"
      where (list_inbox_conversations.tenant is null or v."tenant_id" = list_inbox_conversations.tenant)
        and (filter ->> 'inbox_id' is null or v."inbox_id" = (filter ->> 'inbox_id')::uuid)
        and (coalesce(filter ->> 'status', 'open') = 'all' or v."status" = coalesce(filter ->> 'status', 'open'))
        and (case filter ->> 'assignee'
          when 'me' then v."assignee_id" = (select auth.uid())
          when 'unassigned' then v."assignee_id" is null
          else filter ->> 'assignee' is null or v."assignee_id" = (filter ->> 'assignee')::uuid end)
        and (filter ->> 'team_id' is null or v."team_id" = (filter ->> 'team_id')::uuid)
        and (filter ->> 'contact_id' is null or v."contact_id" = (filter ->> 'contact_id')::uuid)
        and (nullif(filter ->> 'search', '') is null
          or v."subject" ilike '%' || (filter ->> 'search') || '%'
          or v."last_message_preview" ilike '%' || (filter ->> 'search') || '%'
          or c."name" ilike '%' || (filter ->> 'search') || '%'
          or c."email" ilike '%' || (filter ->> 'search') || '%')
        and (filter -> 'before' is null
          or (v."last_message_at", v."id") < ((filter -> 'before' ->> 'last_message_at')::timestamptz, (filter -> 'before' ->> 'id')::uuid))
      order by v."last_message_at" desc, v."id" desc
      limit least(greatest(coalesce((filter ->> 'limit')::integer, 50), 1), 200)
    ) page
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_inbox_messages (
  conversation uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max          integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not "better_supabase"."inbox_conversation_allowed"(list_inbox_messages.conversation::text) then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."inbox_messages_json"(array(
    select m."id" from "better_supabase"."messages" m
    where m."conversation_id" = list_inbox_messages.conversation
      and m."sent_at" is not null
      and (list_inbox_messages.before is null or m."sent_at" < list_inbox_messages.before)
      and (m."kind" = 'message' or "better_supabase"."inbox_note_readable"(list_inbox_messages.conversation))
    order by m."sent_at" desc, m."id" desc
    limit least(greatest(coalesce(list_inbox_messages.max, 50), 1), 200)
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_conversation_read (
  conversation uuid
)
  RETURNS timestamp WITH time zone
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_at timestamptz := clock_timestamp();
  v_conv "better_supabase"."inbox_conversations"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    raise exception 'not allowed to read this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" v where v."id" = mark_conversation_read.conversation;
  insert into "better_supabase"."conversation_members" as k ("conversation_id", "tenant_id", "user_id", "last_read_at")
  values (v_conv."id", v_conv."tenant_id", (select auth.uid()), v_at)
  on conflict ("conversation_id", "user_id") do update set "last_read_at" = greatest(coalesce(k."last_read_at", excluded."last_read_at"), excluded."last_read_at");
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null and exists (select 1 from "better_supabase"."contacts" c where c."id" = v_conv."contact_id" and c."user_id" = (select auth.uid())) then
    perform realtime.send(jsonb_build_object('conversation_id', v_conv."id"), 'read', 'messages:' || v_conv."id"::text, true);
  end if;
  return v_at;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.message_authors (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(y."id"::text, jsonb_build_object('id', pr."id", 'name', coalesce(nullif(pr."full_name", ''), nullif(trim(concat_ws(' ', pr."first_name", pr."last_name")), ''), pr."username"), 'avatarUrl', pr."avatar_url")), '{}'::jsonb)
  from "better_supabase"."messages" y
  join "better_supabase"."profiles" pr on pr."id" = y."author_id"
  where y."id" = any ($1)
    and exists (select 1 from "better_supabase"."conversations" c where c."id" = y."conversation_id" and (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else (coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then coalesce("better_supabase"."can_subject"(c."subject_type", c."subject_id", 'read'), false)
      else false
    end) end))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_inbox_files (
  max integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'conversation_id', d."conversation_id",
    'message_id', d."message_id",
    'tenant_id', x."organization_id",
    'bucket', x."bucket",
    'object_path', x."object_path",
    'name', x."name",
    'mime_type', x."mime_type",
    'source', x."scan_detail"::jsonb -> 'source'
  ) order by x."created_at", x."id"), '[]'::jsonb)
  from (
    select * from "better_supabase"."attachments" y
    where y."status" = 'pending' and y."uploaded_at" is null
      and y."subject_type" = 'message'
      and y."scan_detail" is not null and y."scan_detail" like '{"source"%'
    order by y."created_at", y."id"
    limit least(greatest(coalesce(max, 50), 1), 500)
  ) x
  join "better_supabase"."inbox_message_details" d on d."message_id"::text = x."subject_id";
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_contact (
  contact uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_ids uuid[];
  v_messages integer;
  v_paths jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select c."tenant_id" into v_tenant from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to erase contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_ids := array(select v."id" from "better_supabase"."inbox_conversations" v where v."contact_id" = purge_contact.contact);
  select count(*)::integer into v_messages from "better_supabase"."messages" m where m."conversation_id" = any (v_ids);
  with gone as (
    delete from "better_supabase"."attachments" x
    where (x."subject_type" = 'conversation' and x."subject_id" = any (array(select i::text from unnest(v_ids) i)))
      or (x."subject_type" = 'message' and x."subject_id" in (
        select m."id"::text from "better_supabase"."messages" m where m."conversation_id" = any (v_ids)))
    returning x."bucket" as bucket, x."object_path" as path, x."uploaded_at" as uploaded_at
  )
  select coalesce(jsonb_agg(jsonb_build_object('bucket', g.bucket, 'path', g.path)) filter (where g.uploaded_at is not null), '[]'::jsonb)
  into v_paths from gone g;
  delete from "better_supabase"."conversations" k where k."id" = any (v_ids);
  delete from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  return jsonb_build_object('conversations', cardinality(v_ids), 'messages', v_messages, 'attachments', v_paths);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.react (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  emoji        text,
  present      boolean DEFAULT true,
  actor        text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_actor text;
  v_user uuid;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_actor := coalesce(react.actor, 'service');
  elsif react.actor is not null then
    raise exception 'only the service role reacts for another actor' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  elsif not (coalesce(better_supabase.can('tenant', react.tenant, 'reactions.create'), false) and "better_supabase"."reaction_subject_visible"(react.subject_type, react.subject_id, react.tenant)) then
    raise exception 'not allowed to react to this record' using errcode = '42501', hint = 'REACTION_FORBIDDEN';
  else
    v_user := (select auth.uid());
    v_actor := v_user::text;
  end if;
  if react.emoji is null or length(react.emoji) not between 1 and 64 or react.emoji ~ '\s' then
    raise exception 'emoji must be 1 to 64 characters without spaces' using errcode = '22023', hint = 'REACTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_react"(uuid, text, text, text, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::boolean)', v_hook::oid::regproc)
        using react.tenant, react.subject_type, react.subject_id, react.emoji, coalesce(react.present, true);
    end if;
  end;
  if coalesce(react.present, true) then
    insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
    values (react.tenant, react.subject_type, react.subject_id, v_actor, v_user, react.emoji)
    on conflict do nothing;
  else
    delete from "better_supabase"."reactions" r
    where r."subject_type" = react.subject_type
      and r."subject_id" = react.subject_id
      and r."tenant_id" = react.tenant
      and r."actor" = v_actor
      and r."emoji" = react.emoji;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_react"(uuid, text, text, text, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::boolean)', v_hook::oid::regproc)
        using react.tenant, react.subject_type, react.subject_id, react.emoji, coalesce(react.present, true);
    end if;
  end;
  return "better_supabase"."reaction_list"(react.tenant, react.subject_type, react.subject_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.react_to_inbox_message (
  message uuid,
  emoji   text,
  present boolean DEFAULT true,
  actor   text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_msg "better_supabase"."messages"%rowtype;
  v_conversation uuid;
  v_who text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select m.* into v_msg from "better_supabase"."messages" m
  join "better_supabase"."inbox_message_details" d on d."message_id" = m."id"
  where m."id" = react_to_inbox_message.message and m."deleted_at" is null;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  v_conversation := v_msg."conversation_id";
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(react_to_inbox_message.actor, 'bot');
  elsif v_msg."kind" = 'message' and "better_supabase"."inbox_conversation_allowed"(v_conversation::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg."kind" = 'note' and coalesce(better_supabase.can('tenant', v_msg."tenant_id", 'inbox.reply'), false) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to react to this message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if length(react_to_inbox_message.emoji) not between 1 and 64 then
    raise exception 'emoji must be 1 to 64 characters' using errcode = '22023', hint = 'INBOX_REACTION_INVALID';
  end if;
  if coalesce(react_to_inbox_message.present, true) then
    insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
    values (v_msg."tenant_id", 'message', v_msg."id"::text, v_who, case when v_who ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then v_who::uuid end, react_to_inbox_message.emoji)
    on conflict do nothing;
  else
    delete from "better_supabase"."reactions" x
    where x."subject_type" = 'message' and x."subject_id" = v_msg."id"::text
      and x."actor" = v_who and x."emoji" = react_to_inbox_message.emoji;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(
      jsonb_build_object('conversationId', v_conversation, 'messageId', v_msg."id"),
      'message_updated',
      'messages:' || v_conversation::text,
      true
    );
  end if;
  return coalesce("better_supabase"."reaction_summary"(v_msg."tenant_id", 'message', array[v_msg."id"::text]) -> v_msg."id"::text, '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reaction_subject_visible (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return case reaction_subject_visible.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'engagements.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'calendar.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_delivery (
  message     uuid,
  channel     text,
  external_id text DEFAULT NULL::text,
  status      text DEFAULT 'sent'::text,
  error       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."message_deliveries"%rowtype;
begin
  insert into "better_supabase"."message_deliveries" as d ("tenant_id", "message_id", "channel", "external_id", "status", "error", "attempts")
  select m."tenant_id", m."message_id", record_delivery.channel, record_delivery.external_id, coalesce(record_delivery.status, 'sent'), record_delivery.error, 1
  from "better_supabase"."inbox_message_details" m where m."message_id" = record_delivery.message
  on conflict ("message_id", "channel") do update set
    "external_id" = coalesce(excluded."external_id", d."external_id"),
    "status" = excluded."status",
    "error" = excluded."error",
    "attempts" = d."attempts" + 1
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_inbound (
  input jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact "better_supabase"."contacts"%rowtype;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_message uuid;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_input jsonb := coalesce(input -> 'message', '{}'::jsonb);
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = (input ->> 'inbox_id')::uuid;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if v_contact_input ? 'external_id' and not v_contact_input ? 'identity' then
    v_contact_input := v_contact_input || jsonb_build_object('identity', jsonb_build_object('channel', coalesce(v_contact_input ->> 'channel', v_inbox."channel"), 'external_id', v_contact_input ->> 'external_id'));
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations"
  where "inbox_id" = v_inbox."id" and "thread_id" = input ->> 'thread_id'
  for update;
  if not found then
    v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
    v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
    insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "bot_mode", "thread_id", "metadata")
    values (v_id, v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', v_inbox."bot_mode", input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    if v_contact."user_id" is not null then
      insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact."user_id")
    on conflict do nothing;
    end if;
    v_created := true;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), jsonb_build_object('by', 'channel'));
    perform "better_supabase".emit_event('inbox_conversation.opened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
  end if;
  if v_input ? 'external_id' then
    v_duplicate := exists (select 1 from "better_supabase"."inbox_message_details" d where d."conversation_id" = v_conv."id" and d."external_id" = v_input ->> 'external_id');
  end if;
  v_message := "better_supabase"."inbox_add_message"(
    v_conv."id",
    v_input - 'kind' - 'attachments',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv."id",
    'message_id', v_message,
    'contact_id', v_conv."contact_id",
    'tenant_id', v_conv."tenant_id",
    'created', v_created,
    'duplicate', v_duplicate
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_inbox_message (
  conversation uuid,
  input        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."inbox_conversations" where "id" = send_inbox_message.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif exists (select 1 from "better_supabase"."contacts" c where c."id" = v_conv."contact_id" and c."user_id" = (select auth.uid())) then
    -- The conversation's own contact writes as the contact, staff included.
    if v_kind <> 'message' then
      raise exception 'contacts cannot write notes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    if input ? 'files' then
      raise exception 'contacts attach their own uploads' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  elsif coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    v_author_type := 'agent';
    v_direction := 'outbound';
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_id := "better_supabase"."inbox_add_message"(v_conv."id", coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv."bot_mode" = 'bot' then
    update "better_supabase"."inbox_conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
  end if;
  return "better_supabase"."inbox_messages_json"(array[v_id]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_message (
  conversation uuid,
  body         text,
  attrs        jsonb  DEFAULT '{}'::jsonb,
  attachments  uuid[] DEFAULT '{}'::uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations";
  v_id uuid;
  v_parent uuid := nullif(send_message.attrs ->> 'parentId', '')::uuid;
  v_root uuid;
  v_parsed jsonb := "better_supabase"."parse_mentions"(send_message.body);
  v_mentions uuid[];
  v_scheduled timestamptz := nullif(send_message.attrs ->> 'scheduledFor', '')::timestamptz;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = send_message.conversation;
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if v_conv."kind" = 'inbox' then
    raise exception 'write to an inbox conversation through send_inbox_message' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if v_conv."access" = 'tenant' and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and v_conv."archived_at" is null
    and coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'messages.send'), false) then
    perform "better_supabase"."add_conversation_members"(v_conv."id", array[auth.uid()]);
  end if;
  if not "better_supabase"."can_conversation"(v_conv."id", 'send') then
    raise exception 'not allowed to send messages here' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  if nullif(trim(coalesce(send_message.body, '')), '') is null and cardinality(coalesce(send_message.attachments, '{}')) = 0 then
    raise exception 'a message needs a body or a file' using errcode = '23502', hint = 'MESSAGING_BODY_REQUIRED';
  end if;
  if v_parent is not null then
    select m."thread_id" into v_root from "better_supabase"."messages" m
    where m."id" = v_parent and m."conversation_id" = v_conv."id"
      and m."sent_at" is not null and m."deleted_at" is null;
    if not found then
      raise exception 'reply to a sent message in the same conversation' using errcode = '22023', hint = 'MESSAGING_PARENT_INVALID';
    end if;
    -- One level of threads: a reply to a reply joins the root's thread.
    v_parent := coalesce(v_root, v_parent);
  end if;
  if v_scheduled is not null and v_scheduled <= now() then
    v_scheduled := null;
  end if;
  v_mentions := array(
    select distinct x from (
      select (jsonb_array_elements_text(coalesce(send_message.attrs -> 'mentions', '[]'::jsonb)))::uuid as x
      union
      select (jsonb_array_elements_text(v_parsed -> 'users'))::uuid
    ) s
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_message_send"(uuid, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::jsonb)', v_hook::oid::regproc)
        using send_message.conversation, send_message.body, send_message.attrs;
    end if;
  end;
  begin
    insert into "better_supabase"."messages" ("tenant_id", "conversation_id", "parent_id", "thread_id", "author_id", "body", "document", "anchor",
      "mentions", "mention_scope", "broadcast", "scheduled_for", "sent_at")
    values (v_conv."tenant_id", v_conv."id", v_parent, case when v_parent is null then null else coalesce(v_root, v_parent) end,
      auth.uid(), coalesce(send_message.body, ''), send_message.attrs -> 'document',
      case when v_parent is null then send_message.attrs -> 'anchor' end, v_mentions,
      case when v_conv."access" = 'subject' then null else v_parsed ->> 'scope' end,
      v_parent is not null and coalesce((send_message.attrs ->> 'broadcast')::boolean, false),
      v_scheduled, case when v_scheduled is null then now() end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a message field has an invalid value' using errcode = '22023', hint = 'MESSAGING_MESSAGE_INVALID';
  end;
  -- Files the caller uploaded to the conversation move onto the message.
  if cardinality(coalesce(send_message.attachments, '{}')) > 0 then
    update "better_supabase"."attachments" a
    set "subject_type" = 'message', "subject_id" = v_id::text
    where a."id" = any (send_message.attachments)
      and a."organization_id" = v_conv."tenant_id"
      and a."subject_type" = 'conversation' and a."subject_id" = v_conv."id"::text
      and a."uploaded_by" = auth.uid()
      and a."status" <> 'infected';
    get diagnostics v_count = row_count;
    if v_count <> cardinality(array(select distinct x from unnest(send_message.attachments) x)) then
      raise exception 'attach files you uploaded to this conversation' using errcode = '22023', hint = 'MESSAGING_ATTACHMENT_INVALID';
    end if;
  end if;
  if v_scheduled is null then
    perform "better_supabase"."messaging_message_sent"(v_id);
  else
    perform "better_supabase"."enqueue_job"(queue => 'messaging', payload => jsonb_build_object('type', 'message.publish', 'messageId', v_id), delay => greatest(ceil(extract(epoch from (v_scheduled - now())))::integer, 0), dedupe_key => 'message.publish:' || v_id::text, dedupe_running => false);
    null;
  end if;
  return "better_supabase"."messaging_messages_json"(array[v_id]) -> 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_typing (
  conversation uuid,
  typing       boolean DEFAULT true,
  actor        text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_who text;
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(set_typing.actor, 'bot');
  elsif auth.uid() is null or not "better_supabase"."can_conversation"(set_typing.conversation, 'send') then
    return false;
  else
    v_who := auth.uid()::text;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return false;
  end if;
  perform realtime.send(
    jsonb_build_object('conversationId', set_typing.conversation, 'userId', v_who, 'typing', coalesce(set_typing.typing, true)),
    'typing',
    'messages:' || set_typing.conversation::text,
    true
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_conversation (
  inbox uuid,
  input jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_contact "better_supabase"."contacts"%rowtype;
  v_conv "better_supabase"."inbox_conversations"%rowtype;
  v_id uuid;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = start_conversation.inbox and "archived_at" is null;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  -- A signed-in caller who names no contact on a widget inbox is the
  -- visitor, staff included, so they can try their own widget.
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and (select auth.uid()) is not null and not (input ? 'contact')
    and v_inbox."channel" = 'in_app' and coalesce((v_inbox."settings" ->> 'widget')::boolean, false) then
    v_staff := false;
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  elsif coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_inbox."tenant_id", 'inbox.reply'), false) then
    v_staff := true;
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      raise exception 'input.contact is required' using errcode = '22023', hint = 'CONTACT_REQUIRED';
    end if;
  else
    raise exception 'not allowed to open a conversation in this inbox' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
  v_id := gen_random_uuid();
  insert into "better_supabase"."conversations" ("id", "tenant_id", "kind", "access", "created_by")
  values (v_id, v_inbox."tenant_id", 'inbox', 'tenant', (select auth.uid()));
  insert into "better_supabase"."inbox_conversations" ("id", "tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_id, v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), coalesce(input ->> 'thread_id', 'inbox:' || v_id::text),
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_contact."user_id" is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_contact."user_id")
    on conflict do nothing;
  end if;
  if v_conv."assignee_id" is not null then
    insert into "better_supabase"."conversation_members" ("conversation_id", "tenant_id", "user_id")
    values (v_id, v_inbox."tenant_id", v_conv."assignee_id")
    on conflict do nothing;
  end if;
  insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  perform "better_supabase".emit_event('inbox_conversation.opened', jsonb_build_object('conversationId', v_conv."id", 'organizationId', v_conv."tenant_id"::text, 'inboxId', v_conv."inbox_id", 'contactId', v_conv."contact_id", 'assigneeId', v_conv."assignee_id", 'status', v_conv."status"), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id")::text, null, 'better-supabase/inbox');
  if input ? 'message' then
    perform "better_supabase"."inbox_add_message"(
      v_conv."id",
      case when jsonb_typeof(input -> 'message') = 'string' then jsonb_build_object('body', input ->> 'message') else input -> 'message' end,
      case when v_staff then (case when (select auth.uid()) is null then 'bot' else 'agent' end) else 'contact' end,
      (select auth.uid()),
      case when v_staff then 'outbound' else 'inbound' end
    );
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unread_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_object_agg(k."conversation_id"::text, jsonb_build_object('unread', u.unread, 'mentions', u.mentions)), '{}'::jsonb)
  from "better_supabase"."conversation_members" k
  cross join lateral (
    select count(*) as unread,
      count(*) filter (where auth.uid() = any (m."mentions") or m."mention_scope" is not null) as mentions
    from "better_supabase"."messages" m
    where m."conversation_id" = k."conversation_id"
      and (m."thread_id" is null or m."broadcast")
      and m."sent_at" > coalesce(k."last_read_at", '-infinity'::timestamptz)
      and m."deleted_at" is null
      and m."author_id" is distinct from auth.uid()
  ) u
  where k."user_id" = auth.uid()
    and k."tenant_id" = unread_counts.tenant
    and not exists (select 1 from "better_supabase"."conversations" c where c."id" = k."conversation_id" and c."kind" = 'inbox')
    and u.unread > 0
$function$;

ALTER TABLE "better_supabase"."inbox_conversations"
  ADD CONSTRAINT "inbox_conversations_core_fkey" FOREIGN KEY (id) REFERENCES better_supabase.conversations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."inbox_message_details"
  ADD CONSTRAINT "inbox_message_details_core_fkey" FOREIGN KEY (message_id) REFERENCES better_supabase.messages(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."message_deliveries"
  ADD CONSTRAINT "message_deliveries_message_id_fkey" FOREIGN KEY (message_id) REFERENCES better_supabase.inbox_message_details(message_id) ON DELETE CASCADE;

CREATE TRIGGER bs_messaging_inbox_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.inbox_message_broadcast();

CREATE POLICY "conversations_read" ON "better_supabase"."conversations"
  FOR SELECT
  TO "authenticated"
  USING (
CASE
    WHEN (kind = 'inbox'::text) THEN better_supabase.inbox_conversation_allowed((id)::text)
    ELSE ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)) AND
    CASE access
        WHEN 'tenant'::text THEN true
        WHEN 'members'::text THEN better_supabase.is_conversation_member(id)
        WHEN 'subject'::text THEN COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
        ELSE false
    END)
END);

CREATE POLICY "inbox_message_details_staff_read" ON "better_supabase"."inbox_message_details"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "messages_read" ON "better_supabase"."messages"
  FOR SELECT
  TO "authenticated"
  USING ((((sent_at IS NOT NULL) OR (author_id = ( SELECT auth.uid() AS uid))) AND (EXISTS ( SELECT 1
   FROM better_supabase.conversations c
  WHERE (c.id = messages.conversation_id))) AND ((kind = 'message'::text) OR better_supabase.inbox_note_readable(conversation_id))));

CREATE POLICY "reactions_delete" ON "better_supabase"."reactions"
  FOR DELETE
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "reactions_insert" ON "better_supabase"."reactions"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((user_id = ( SELECT auth.uid() AS uid)) AND (actor = (( SELECT auth.uid() AS uid))::text) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('reactions.create'::text)
    AS tenant_ids_with)) AND better_supabase.reaction_subject_visible(subject_type, subject_id, tenant_id) AND ( SELECT better_supabase.actor_may_write() AS actor_may_write)));

CREATE POLICY "bs_inbox_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'inbox:org:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 11) IN ( SELECT (x.x)::text
    AS x
   FROM better_supabase.tenant_ids_with('inbox.read'::text) x(x)))));

CREATE POLICY "bs_inbox_files_read" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (better_supabase.inbox_file_allowed(bucket_id, name));

REVOKE ALL ON FUNCTION "api"."create_inbox_attachment"(uuid, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_inbox_attachment"(uuid, text, text, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."inbox_file_failed"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."inbox_file_failed"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."pending_inbox_files"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pending_inbox_files"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."react_to_inbox_message"(uuid, text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."react_to_inbox_message"(uuid, text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_typing"(uuid, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_typing"(uuid, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_inbox_attachment"(uuid, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_inbox_attachment"(uuid, text, text, bigint) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_add_message"(uuid, jsonb, text, uuid, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."inbox_can_conversation"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_can_conversation"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_contact_read_at"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_contact_read_at"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_conversation_json"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_conversation_json"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_counts"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_counts"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_file_allowed"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_file_allowed"(text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_file_failed"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_file_failed"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_messages_json"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_messages_json"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_note_readable"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_note_readable"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_inbox_conversations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_inbox_conversations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_inbox_messages"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_inbox_messages"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pending_inbox_files"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pending_inbox_files"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."react_to_inbox_message"(uuid, text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."react_to_inbox_message"(uuid, text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_typing"(uuid, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_typing"(uuid, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON TABLE "better_supabase"."inbox_message_details" FROM "authenticated";

GRANT SELECT ON TABLE "better_supabase"."inbox_message_details" TO "authenticated";

REVOKE ALL ON TABLE "better_supabase"."inbox_message_details" FROM "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inbox_message_details" TO "service_role";
