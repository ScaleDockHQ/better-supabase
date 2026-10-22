SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."mail_accounts" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid                     NOT NULL,
  "user_id"        uuid                     NOT NULL,
  "provider"       text                     NOT NULL,
  "address"        text                     NOT NULL,
  "credential_ref" jsonb                    NOT NULL,
  "share"          text                     NOT NULL DEFAULT 'records'::text,
  "status"         text                     NOT NULL DEFAULT 'active'::text,
  "sync_cursor"    text,
  "last_synced_at" timestamp with time zone,
  "last_error"     text,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "mail_accounts_address_check" CHECK (((address = lower(address)) AND (address ~ '^[^@[:space:]]+@[^@[:space:]]+$'::text))),
  CONSTRAINT "mail_accounts_credential_ref_check" CHECK ((jsonb_typeof(credential_ref) = 'object'::text)),
  CONSTRAINT "mail_accounts_pkey" PRIMARY KEY (id),
  CONSTRAINT "mail_accounts_provider_check" CHECK ((provider ~ '^[a-z][a-z0-9-]{0,39}$'::text)),
  CONSTRAINT "mail_accounts_share_check" CHECK ((share = ANY (ARRAY['records'::text, 'private'::text]))),
  CONSTRAINT "mail_accounts_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'error'::text, 'disconnected'::text]))),
  CONSTRAINT "mail_accounts_tenant_id_user_id_address_key" UNIQUE (tenant_id, user_id, address)
);

ALTER TABLE "better_supabase"."mail_accounts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."mail_messages" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid                     NOT NULL,
  "account_id"     uuid                     NOT NULL,
  "thread_id"      uuid                     NOT NULL,
  "external_id"    text                     NOT NULL,
  "rfc_message_id" text,
  "direction"      text                     NOT NULL,
  "from_address"   text,
  "from_name"      text,
  "to_addresses"   text[]                   NOT NULL DEFAULT '{}'::text[],
  "cc_addresses"   text[]                   NOT NULL DEFAULT '{}'::text[],
  "subject"        text,
  "snippet"        text,
  "body_text"      text,
  "body_html"      text,
  "sent_at"        timestamp with time zone NOT NULL,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "mail_messages_account_id_external_id_key" UNIQUE (account_id, external_id),
  CONSTRAINT "mail_messages_direction_check" CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text]))),
  CONSTRAINT "mail_messages_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."mail_messages"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."mail_thread_subjects" (
  "tenant_id"    uuid                     NOT NULL,
  "thread_id"    uuid                     NOT NULL,
  "subject_type" text                     NOT NULL,
  "subject_id"   text                     NOT NULL,
  "source"       text                     NOT NULL DEFAULT 'match'::text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "mail_thread_subjects_pkey" PRIMARY KEY (thread_id, subject_type, subject_id),
  CONSTRAINT "mail_thread_subjects_source_check" CHECK ((source = ANY (ARRAY['match'::text, 'manual'::text])))
);

ALTER TABLE "better_supabase"."mail_thread_subjects"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."mail_threads" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "account_id"      uuid                     NOT NULL,
  "external_id"     text                     NOT NULL,
  "subject"         text,
  "snippet"         text,
  "last_message_at" timestamp with time zone,
  "message_count"   integer                  NOT NULL DEFAULT 0,
  "engagement_id"   uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "mail_threads_account_id_external_id_key" UNIQUE (account_id, external_id),
  CONSTRAINT "mail_threads_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."mail_threads"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.connect_mail_account (
  tenant         uuid,
  provider       text,
  address        text,
  credential_ref jsonb,
  share          text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."connect_mail_account"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.disconnect_mail_account (
  account uuid,
  purge   boolean
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."disconnect_mail_account"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.due_mail_accounts (
  max_count   integer,
  stale_after interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."due_mail_accounts"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_mail_account (
  account uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_mail_account"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_mail_thread (
  thread uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_mail_thread"($1) $function$;

CREATE OR REPLACE FUNCTION api.ingest_mail (
  account     uuid,
  messages    jsonb,
  next_cursor text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ingest_mail"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.link_mail_thread (
  thread   uuid,
  subjects jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."link_mail_thread"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_mail_threads (
  tenant    uuid,
  account   uuid,
  before    timestamp with time zone,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_mail_threads"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.mail_accounts_of (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mail_accounts_of"($1) $function$;

CREATE OR REPLACE FUNCTION api.mail_thread_visible (
  thread uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mail_thread_visible"($1) $function$;

CREATE OR REPLACE FUNCTION api.mail_threads_of (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone,
  page_size    integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mail_threads_of"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.record_sent_mail (
  account uuid,
  message jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_sent_mail"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_mail_account_status (
  account uuid,
  status  text,
  error   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_mail_account_status"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.unlink_mail_thread (
  thread       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."unlink_mail_thread"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.update_mail_account (
  account uuid,
  share   text,
  paused  boolean
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_mail_account"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.connect_mail_account (
  tenant         uuid,
  provider       text,
  address        text,
  credential_ref jsonb,
  share          text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."mail_accounts";
  v_address text := lower(trim(connect_mail_account.address));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', connect_mail_account.tenant, 'mail.connect'), false) then
    raise exception 'not allowed to connect a mailbox' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if connect_mail_account.provider is null or connect_mail_account.provider !~ '^[a-z][a-z0-9-]{0,39}$' then
    raise exception 'provider is a lowercase name' using errcode = '22023', hint = 'MAIL_PROVIDER_INVALID';
  end if;
  if v_address is null or v_address !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    raise exception 'address is an email address' using errcode = '22023', hint = 'MAIL_ADDRESS_INVALID';
  end if;
  if coalesce(connect_mail_account.share, 'records') not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  if jsonb_typeof(connect_mail_account.credential_ref) is distinct from 'object' then
    raise exception 'credential_ref is a credential reference' using errcode = '22023', hint = 'MAIL_CREDENTIAL_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) and connect_mail_account.credential_ref is not null and jsonb_typeof(connect_mail_account.credential_ref) <> 'null'
    and (jsonb_typeof(connect_mail_account.credential_ref -> 'tenant') is distinct from 'string' or (connect_mail_account.credential_ref ->> 'tenant') is distinct from (connect_mail_account.tenant)::text) then
    raise exception 'credential_ref must carry the tenant % that owns it', connect_mail_account.tenant
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;
  insert into "better_supabase"."mail_accounts" as x ("tenant_id", "user_id", "provider", "address", "credential_ref", "share")
  values (connect_mail_account.tenant, auth.uid(), connect_mail_account.provider, v_address, connect_mail_account.credential_ref, coalesce(connect_mail_account.share, 'records'))
  on conflict ("tenant_id", "user_id", "address") do update set
    "provider" = excluded."provider",
    "credential_ref" = excluded."credential_ref",
    "share" = excluded."share",
    "status" = 'active',
    "sync_cursor" = case when x."provider" = excluded."provider" then x."sync_cursor" end,
    "last_error" = null,
    "updated_at" = now()
  returning * into v_row;
  perform "better_supabase".emit_event('mail_account.connected', jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address"), 'mail-accounts/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/mail-sync');
  perform better_supabase.audit_event(
    event_type => 'mail_account.connected',
    category => 'integration',
    target_type => 'mail_account',
    record_id => v_row."id"::text,
    target_label => v_row."address",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.data_lifecycle_credentials()
  RETURNS TABLE (
    name     text,
    tbl      text,
    col      text,
    user_col text
  )
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select * from (values
    ('better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'credential_ref', null::text),
    ('better_supabase.workflow_credentials', '"better_supabase"."workflow_credentials"', 'credential_ref', null::text),
    ('better_supabase.chat_installations', '"better_supabase"."chat_installations"', 'credential_ref', null::text),
    ('better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'credential_ref', null::text),
    ('better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'credential_ref', 'user_id'),
    ('better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'credential_ref', null::text),
    ('better_supabase.mail_accounts', '"better_supabase"."mail_accounts"', 'credential_ref', 'user_id')
  ) as c(name, tbl, col, user_col)
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
    ('organization', 'better_supabase.mail_thread_subjects', '"better_supabase"."mail_thread_subjects"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.disconnect_mail_account (
  account uuid,
  purge   boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."mail_accounts" x
  where x."id" = disconnect_mail_account.account
    and (x."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.manage'), false));
  if v_row."id" is null then
    return false;
  end if;
  if coalesce(disconnect_mail_account.purge, false) then
    delete from "better_supabase"."mail_accounts" x where x."id" = v_row."id";
  else
    update "better_supabase"."mail_accounts" x set "status" = 'disconnected', "sync_cursor" = null, "updated_at" = now()
    where x."id" = v_row."id";
  end if;
  perform "better_supabase".emit_event('mail_account.disconnected', jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address"), 'mail-accounts/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/mail-sync');
  perform better_supabase.audit_event(
    event_type => 'mail_account.disconnected',
    category => 'integration',
    target_type => 'mail_account',
    record_id => v_row."id"::text,
    target_label => v_row."address",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'accountId', v_row."id", 'userId', v_row."user_id", 'provider', v_row."provider", 'address', v_row."address")
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.due_mail_accounts (
  max_count   integer,
  stale_after interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(p) order by p."last_synced_at" nulls first, p."id"), '[]'::jsonb)
    from (
      select * from "better_supabase"."mail_accounts" x
      where x."status" = 'active'
        and (x."last_synced_at" is null or x."last_synced_at" < now() - coalesce(due_mail_accounts.stale_after, interval '5 minutes'))
      order by x."last_synced_at" nulls first, x."id"
      limit least(greatest(coalesce(due_mail_accounts.max_count, 25), 1), 500)
    ) p
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_mail_account (
  account uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) from "better_supabase"."mail_accounts" x where x."id" = get_mail_account.account
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_mail_thread (
  thread uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('messages', coalesce((
    select jsonb_agg(to_jsonb(y) order by y."sent_at", y."id")
    from "better_supabase"."mail_messages" y where y."thread_id" = x."id"
  ), '[]'::jsonb))
  from "better_supabase"."mail_threads" x
  where x."id" = get_mail_thread.thread
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ingest_mail (
  account     uuid,
  messages    jsonb,
  next_cursor text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_account record;
  v_item jsonb;
  v_stored jsonb;
  v_new jsonb := '[]'::jsonb;
  v_threads uuid[] := '{}';
  v_thread uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k where k."id" = ingest_mail.account and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such connected mailbox' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(ingest_mail.messages, '[]')) <> 'array' then
    raise exception 'messages is a list' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  if jsonb_array_length(coalesce(ingest_mail.messages, '[]')) > 500 then
    raise exception 'at most 500 messages per call' using errcode = '22023', hint = 'MAIL_BATCH_TOO_LARGE';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(ingest_mail.messages, '[]')) loop
    v_stored := "better_supabase"."store_mail_message"(v_account.id, v_item);
    if not ((v_stored ->> 'threadId')::uuid = any (v_threads)) then
      v_threads := v_threads || (v_stored ->> 'threadId')::uuid;
    end if;
    if (v_stored ->> 'created')::boolean then
      v_new := v_new || jsonb_build_array(v_stored || jsonb_build_object('fromAddress', lower(coalesce(v_item -> 'from' ->> 'address', v_item ->> 'from'))));
    end if;
  end loop;
  foreach v_thread in array v_threads loop
    perform "better_supabase"."match_mail_thread"(v_thread);
    perform "better_supabase"."log_mail_thread"(v_thread);
  end loop;
  for v_stored in select value from jsonb_array_elements(v_new) loop
    if v_stored ->> 'direction' = 'outbound' then
      perform "better_supabase".emit_event('mail_message.sent', jsonb_build_object('organizationId', v_account.tenant, 'accountId', v_account.id, 'userId', v_account.owner, 'threadId', v_stored ->> 'threadId', 'messageId', v_stored ->> 'id', 'direction', v_stored ->> 'direction', 'fromAddress', v_stored ->> 'fromAddress', 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = (v_stored ->> 'threadId')::uuid), '[]'::jsonb)), 'mail-messages/' || (v_stored ->> 'id'), (v_account.tenant::text)::text, 'mail_message:' || (v_stored ->> 'id'), 'better-supabase/mail-sync');
    else
      perform "better_supabase".emit_event('mail_message.received', jsonb_build_object('organizationId', v_account.tenant, 'accountId', v_account.id, 'userId', v_account.owner, 'threadId', v_stored ->> 'threadId', 'messageId', v_stored ->> 'id', 'direction', v_stored ->> 'direction', 'fromAddress', v_stored ->> 'fromAddress', 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = (v_stored ->> 'threadId')::uuid), '[]'::jsonb)), 'mail-messages/' || (v_stored ->> 'id'), (v_account.tenant::text)::text, 'mail_message:' || (v_stored ->> 'id'), 'better-supabase/mail-sync');
    end if;
  end loop;
  update "better_supabase"."mail_accounts" x set
    "sync_cursor" = coalesce(ingest_mail.next_cursor, x."sync_cursor"),
    "last_synced_at" = now(),
    "status" = case when x."status" = 'error' then 'active' else x."status" end,
    "last_error" = null,
    "updated_at" = now()
  where x."id" = v_account.id;
  return jsonb_build_object('stored', jsonb_array_length(v_new), 'threads', coalesce(array_length(v_threads, 1), 0));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link_mail_thread (
  thread   uuid,
  subjects jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_thread uuid := link_mail_thread.thread;
  v_tenant uuid;
  v_item jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = v_thread and k."user_id" = auth.uid();
  if v_tenant is null then
    raise exception 'no such thread in your mailbox' using errcode = 'P0002', hint = 'MAIL_THREAD_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(link_mail_thread.subjects, '[]')) <> 'array' then
    raise exception 'subjects must be a list of { type, id }' using errcode = '22023', hint = 'MAIL_SUBJECTS_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(link_mail_thread.subjects, '[]')) loop
    if not (case (v_item ->> 'type')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'id'))::uuid and s."tenant_id"::text = v_tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'id'))::uuid and s."organization_id"::text = v_tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'type'), (v_item ->> 'id'), 'read')) then
      raise exception 'a subject is unknown or not readable in this organization' using errcode = '42501', hint = 'MAIL_SUBJECT_FORBIDDEN';
    end if;
    insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id", "source")
    values (v_tenant, v_thread, v_item ->> 'type', v_item ->> 'id', 'manual')
    on conflict ("thread_id", "subject_type", "subject_id") do update set "source" = 'manual';
  end loop;
  perform "better_supabase"."log_mail_thread"(v_thread);
  return (select to_jsonb(x) || jsonb_build_object('subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) from "better_supabase"."mail_threads" x where x."id" = v_thread);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_mail_threads (
  tenant    uuid,
  account   uuid,
  before    timestamp with time zone,
  page_size integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    where x."tenant_id" = list_mail_threads.tenant
      and (list_mail_threads.account is null or x."account_id" = list_mail_threads.account)
      and (list_mail_threads.before is null or x."last_message_at" < list_mail_threads.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(list_mail_threads.page_size, 25), 1), 100)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_mail_thread (
  thread uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row record;
  v_subjects jsonb;
  v_result jsonb;
  v_claims text;
begin
  select x."id" as id, x."tenant_id" as tenant, x."subject" as subject, x."snippet" as snippet,
    x."last_message_at" as at, k."user_id" as owner, k."share" as share
  into v_row
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = log_mail_thread.thread;
  if v_row.id is null or v_row.share <> 'records' then
    return;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id"), '[]'::jsonb)
  into v_subjects
  from "better_supabase"."mail_thread_subjects" s where s."thread_id" = v_row.id;
  if jsonb_array_length(v_subjects) = 0 then
    return;
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_result := "better_supabase"."log_engagement"(v_row.tenant, jsonb_build_object(
    'type', 'email',
    'title', coalesce(nullif(trim(v_row.subject), ''), '(no subject)'),
    'body', v_row.snippet,
    'ownerId', v_row.owner,
    'doneAt', v_row.at,
    'externalRef', 'mail:' || v_row.id::text
  ), v_subjects);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  update "better_supabase"."mail_threads" x set "engagement_id" = (v_result ->> 'id')::uuid
  where x."id" = v_row.id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mail_accounts_of (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at", x."id"), '[]'::jsonb)
  from "better_supabase"."mail_accounts" x
  where x."tenant_id" = mail_accounts_of.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mail_thread_visible (
  thread uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
    where x."id" = $1
      and (k."user_id" = auth.uid() or (
        k."share" = 'records'
        and coalesce(better_supabase.can('tenant', x."tenant_id", 'mail.read'), false)
        and exists (
          select 1 from "better_supabase"."mail_thread_subjects" s
          where s."thread_id" = x."id"
            and "better_supabase"."can_subject"(s."subject_type", s."subject_id", 'read')
        )
      ))
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mail_threads_of (
  subject_type text,
  subject_id   text,
  before       timestamp with time zone,
  page_size    integer
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(p.value order by p.at desc, p.id desc), '[]'::jsonb)
  from (
    select to_jsonb(x) || jsonb_build_object('address', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = x."account_id"), 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = x."id"), '[]'::jsonb)) as value, x."last_message_at" as at, x."id" as id
    from "better_supabase"."mail_threads" x
    join "better_supabase"."mail_thread_subjects" s on s."thread_id" = x."id"
    where s."subject_type" = mail_threads_of.subject_type and s."subject_id" = mail_threads_of.subject_id
      and (mail_threads_of.before is null or x."last_message_at" < mail_threads_of.before)
    order by x."last_message_at" desc, x."id" desc
    limit least(greatest(coalesce(mail_threads_of.page_size, 25), 1), 100)
  ) p
$function$;

CREATE OR REPLACE FUNCTION better_supabase.match_mail_thread (
  thread uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_thread uuid := match_mail_thread.thread;
  v_tenant uuid;
  v_own text;
  v_addresses text[];
begin
  select x."tenant_id", k."address" into v_tenant, v_own
  from "better_supabase"."mail_threads" x join "better_supabase"."mail_accounts" k on k."id" = x."account_id"
  where x."id" = v_thread;
  select coalesce(array_agg(distinct v.address), '{}') into v_addresses
  from "better_supabase"."mail_messages" y
  cross join lateral unnest(array[y."from_address"] || y."to_addresses" || y."cc_addresses") as v(address)
  where y."thread_id" = v_thread and v.address is not null and v.address <> v_own;
  insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id")
  select v_tenant, v_thread, 'person', p."id"::text
  from "better_supabase"."people" p
  where p."tenant_id" = v_tenant and p."archived_at" is null
    and lower(p."email") = any (v_addresses)
  on conflict do nothing;
  insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id")
  select v_tenant, v_thread, 'company', cp."company_id"::text
  from "better_supabase"."company_people" cp
  join "better_supabase"."people" p on p."id" = cp."person_id"
  where p."tenant_id" = v_tenant and p."archived_at" is null
    and lower(p."email") = any (v_addresses)
  on conflict do nothing;
  insert into "better_supabase"."mail_thread_subjects" ("tenant_id", "thread_id", "subject_type", "subject_id")
  select v_tenant, v_thread, 'company', c."id"::text
  from "better_supabase"."companies" c
  where c."tenant_id" = v_tenant and c."archived_at" is null
    and c."domain" is not null
    and lower(c."domain") = any (select split_part(x, '@', 2) from unnest(v_addresses) x)
  on conflict do nothing;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_sent_mail (
  account uuid,
  message jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_account record;
  v_stored jsonb;
  v_thread uuid;
begin
  select k."id" as id, k."tenant_id" as tenant, k."user_id" as owner into v_account
  from "better_supabase"."mail_accounts" k
  where k."id" = record_sent_mail.account and k."user_id" = auth.uid() and k."status" <> 'disconnected';
  if v_account.id is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.can('tenant', v_account.tenant, 'mail.send'), false) then
    raise exception 'not allowed to send mail' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  v_stored := "better_supabase"."store_mail_message"(v_account.id, coalesce(record_sent_mail.message, '{}'::jsonb) || '{"direction": "outbound"}'::jsonb);
  v_thread := (v_stored ->> 'threadId')::uuid;
  perform "better_supabase"."match_mail_thread"(v_thread);
  perform "better_supabase"."log_mail_thread"(v_thread);
  if (v_stored ->> 'created')::boolean then
    v_stored := v_stored || jsonb_build_object('fromAddress', (select k."address" from "better_supabase"."mail_accounts" k where k."id" = v_account.id));
    perform "better_supabase".emit_event('mail_message.sent', jsonb_build_object('organizationId', v_account.tenant, 'accountId', v_account.id, 'userId', v_account.owner, 'threadId', v_stored ->> 'threadId', 'messageId', v_stored ->> 'id', 'direction', v_stored ->> 'direction', 'fromAddress', v_stored ->> 'fromAddress', 'subjects', coalesce((select jsonb_agg(jsonb_build_object('type', s."subject_type", 'id', s."subject_id") order by s."created_at", s."subject_type", s."subject_id") from "better_supabase"."mail_thread_subjects" s where s."thread_id" = (v_stored ->> 'threadId')::uuid), '[]'::jsonb)), 'mail-messages/' || (v_stored ->> 'id'), (v_account.tenant::text)::text, 'mail_message:' || (v_stored ->> 'id'), 'better-supabase/mail-sync');
  end if;
  return (select to_jsonb(y) from "better_supabase"."mail_messages" y where y."id" = (v_stored ->> 'id')::uuid);
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
      'mail.read', 'mail.connect', 'mail.send', 'mail.manage'
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
      'mail.read', 'mail.connect', 'mail.send'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_mail_account_status (
  account uuid,
  status  text,
  error   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role syncs mailboxes' using errcode = '42501', hint = 'MAIL_FORBIDDEN';
  end if;
  if set_mail_account_status.status not in ('active', 'paused', 'error') then
    raise exception 'status is active, paused or error' using errcode = '22023', hint = 'MAIL_STATUS_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "status" = set_mail_account_status.status,
    "last_error" = left(set_mail_account_status.error, 1000),
    "last_synced_at" = now(),
    "updated_at" = now()
  where x."id" = set_mail_account_status.account and x."status" <> 'disconnected';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.store_mail_message (
  account uuid,
  message jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_account record;
  v_external text := nullif(trim(store_mail_message.message ->> 'externalId'), '');
  v_thread_ref text := coalesce(nullif(trim(store_mail_message.message ->> 'threadId'), ''), nullif(trim(store_mail_message.message ->> 'externalId'), ''));
  v_rfc text := nullif(trim(store_mail_message.message ->> 'messageId'), '');
  v_from text := lower(coalesce(nullif(trim(store_mail_message.message -> 'from' ->> 'address'), ''), case when jsonb_typeof(store_mail_message.message -> 'from') = 'string' then nullif(trim(store_mail_message.message ->> 'from'), '') end));
  v_direction text := nullif(trim(store_mail_message.message ->> 'direction'), '');
  v_sent timestamptz;
  v_thread uuid;
  v_id uuid;
begin
  select k."id" as id, k."tenant_id" as tenant, k."address" as address into v_account
  from "better_supabase"."mail_accounts" k where k."id" = store_mail_message.account;
  if jsonb_typeof(store_mail_message.message) <> 'object' or v_external is null or nullif(trim(store_mail_message.message ->> 'sentAt'), '') is null then
    raise exception 'a message needs an externalId and a sentAt' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  v_sent := (nullif(trim(store_mail_message.message ->> 'sentAt'), ''))::timestamptz;
  v_direction := coalesce(v_direction, case when v_from = v_account.address then 'outbound' else 'inbound' end);
  if v_direction not in ('inbound', 'outbound') then
    raise exception 'direction is inbound or outbound' using errcode = '22023', hint = 'MAIL_MESSAGE_INVALID';
  end if;
  insert into "better_supabase"."mail_threads" ("tenant_id", "account_id", "external_id")
  values (v_account.tenant, v_account.id, v_thread_ref)
  on conflict ("account_id", "external_id") do update set "updated_at" = now()
  returning "id" into v_thread;
  select y."id" into v_id from "better_supabase"."mail_messages" y
  where y."account_id" = v_account.id
    and (y."external_id" = v_external or (v_rfc is not null and y."rfc_message_id" = v_rfc))
  order by y."external_id" = v_external desc
  limit 1;
  if v_id is not null then
    update "better_supabase"."mail_messages" y set "external_id" = v_external, "rfc_message_id" = coalesce(v_rfc, y."rfc_message_id")
    where y."id" = v_id
      and not exists (select 1 from "better_supabase"."mail_messages" z where z."account_id" = v_account.id and z."external_id" = v_external and z."id" <> v_id);
    return jsonb_build_object('id', v_id, 'threadId', (select y."thread_id" from "better_supabase"."mail_messages" y where y."id" = v_id), 'created', false, 'direction', v_direction);
  end if;
  insert into "better_supabase"."mail_messages" ("tenant_id", "account_id", "thread_id", "external_id", "rfc_message_id", "direction",
    "from_address", "from_name", "to_addresses", "cc_addresses", "subject", "snippet", "body_text", "body_html", "sent_at")
  values (v_account.tenant, v_account.id, v_thread, v_external, v_rfc, v_direction,
    v_from, nullif(trim(store_mail_message.message -> 'from' ->> 'name'), ''), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'to') = 'array' then store_mail_message.message -> 'to' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'), coalesce((select array_agg(lower(trim(coalesce(e.value ->> 'address', e.value #>> '{}')))) from jsonb_array_elements(case when jsonb_typeof(store_mail_message.message -> 'cc') = 'array' then store_mail_message.message -> 'cc' else '[]'::jsonb end) e where coalesce(e.value ->> 'address', e.value #>> '{}') like '%@%'), '{}'),
    nullif(trim(store_mail_message.message ->> 'subject'), ''), left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500), store_mail_message.message ->> 'text', store_mail_message.message ->> 'html', v_sent)
  returning "id" into v_id;
  update "better_supabase"."mail_threads" x set
    "subject" = coalesce(x."subject", nullif(trim(store_mail_message.message ->> 'subject'), '')),
    "snippet" = case when x."last_message_at" is null or v_sent >= x."last_message_at" then left(nullif(trim(store_mail_message.message ->> 'snippet'), ''), 500) else x."snippet" end,
    "last_message_at" = greatest(x."last_message_at", v_sent),
    "message_count" = x."message_count" + 1,
    "updated_at" = now()
  where x."id" = v_thread;
  return jsonb_build_object('id', v_id, 'threadId', v_thread, 'created', true, 'direction', v_direction);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlink_mail_thread (
  thread       uuid,
  subject_type text,
  subject_id   text
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
  delete from "better_supabase"."mail_thread_subjects" s
  using "better_supabase"."mail_threads" x, "better_supabase"."mail_accounts" k
  where s."thread_id" = unlink_mail_thread.thread
    and s."subject_type" = unlink_mail_thread.subject_type and s."subject_id" = unlink_mail_thread.subject_id
    and x."id" = s."thread_id" and k."id" = x."account_id" and k."user_id" = auth.uid();
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_mail_account (
  account uuid,
  share   text,
  paused  boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."mail_accounts";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if update_mail_account.share is not null and update_mail_account.share not in ('records', 'private') then
    raise exception 'share is records or private' using errcode = '22023', hint = 'MAIL_SHARE_INVALID';
  end if;
  update "better_supabase"."mail_accounts" x set
    "share" = coalesce(update_mail_account.share, x."share"),
    "status" = case
      when update_mail_account.paused then 'paused'
      when update_mail_account.paused = false and x."status" = 'paused' then 'active'
      else x."status" end,
    "updated_at" = now()
  where x."id" = update_mail_account.account and x."user_id" = auth.uid() and x."status" <> 'disconnected'
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'no such mailbox of yours' using errcode = 'P0002', hint = 'MAIL_ACCOUNT_NOT_FOUND';
  end if;
  return to_jsonb(v_row);
end;
$function$;

ALTER TABLE "better_supabase"."mail_accounts"
  ADD CONSTRAINT "mail_accounts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."mail_messages"
  ADD CONSTRAINT "mail_messages_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.mail_accounts(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."mail_threads"
  ADD CONSTRAINT "mail_threads_account_id_fkey" FOREIGN KEY (account_id) REFERENCES better_supabase.mail_accounts(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."mail_threads"
  ADD CONSTRAINT "mail_threads_engagement_id_fkey" FOREIGN KEY (engagement_id) REFERENCES better_supabase.engagements(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."mail_messages"
  ADD CONSTRAINT "mail_messages_thread_id_fkey" FOREIGN KEY (thread_id) REFERENCES better_supabase.mail_threads(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."mail_thread_subjects"
  ADD CONSTRAINT "mail_thread_subjects_thread_id_fkey" FOREIGN KEY (thread_id) REFERENCES better_supabase.mail_threads(id) ON DELETE CASCADE;

CREATE INDEX mail_accounts_due_idx ON better_supabase.mail_accounts USING btree (last_synced_at NULLS FIRST)
  WHERE (status = 'active'::text);

CREATE INDEX mail_accounts_user_idx ON better_supabase.mail_accounts USING btree (user_id);

CREATE INDEX mail_messages_rfc_idx ON better_supabase.mail_messages USING btree (account_id, rfc_message_id)
  WHERE (rfc_message_id IS NOT NULL);

CREATE INDEX mail_messages_thread_idx ON better_supabase.mail_messages USING btree (thread_id, sent_at);

CREATE INDEX mail_thread_subjects_subject_idx ON better_supabase.mail_thread_subjects USING btree (subject_type, subject_id);

CREATE INDEX mail_threads_engagement_idx ON better_supabase.mail_threads USING btree (engagement_id)
  WHERE (engagement_id IS NOT NULL);

CREATE INDEX mail_threads_tenant_recent_idx ON better_supabase.mail_threads USING btree (tenant_id, last_message_at DESC);

CREATE POLICY "mail_accounts_read" ON "better_supabase"."mail_accounts"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('mail.manage'::text) AS tenant_ids_with))));

CREATE POLICY "mail_messages_read" ON "better_supabase"."mail_messages"
  FOR SELECT
  TO "authenticated"
  USING (better_supabase.mail_thread_visible(thread_id));

CREATE POLICY "mail_thread_subjects_read" ON "better_supabase"."mail_thread_subjects"
  FOR SELECT
  TO "authenticated"
  USING (better_supabase.mail_thread_visible(thread_id));

CREATE POLICY "mail_threads_read" ON "better_supabase"."mail_threads"
  FOR SELECT
  TO "authenticated"
  USING (better_supabase.mail_thread_visible(id));

REVOKE ALL ON FUNCTION "api"."connect_mail_account"(uuid, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."connect_mail_account"(uuid, text, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."disconnect_mail_account"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."disconnect_mail_account"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."due_mail_accounts"(integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."due_mail_accounts"(integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_mail_account"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_mail_account"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_mail_thread"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_mail_thread"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ingest_mail"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ingest_mail"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."link_mail_thread"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."link_mail_thread"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_mail_threads"(uuid, uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_mail_threads"(uuid, uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mail_accounts_of"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mail_accounts_of"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mail_thread_visible"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mail_thread_visible"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mail_threads_of"(text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mail_threads_of"(text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_sent_mail"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_sent_mail"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_mail_account_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_mail_account_status"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."unlink_mail_thread"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."unlink_mail_thread"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_mail_account"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_mail_account"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."connect_mail_account"(uuid, text, text, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."disconnect_mail_account"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."disconnect_mail_account"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."due_mail_accounts"(integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."due_mail_accounts"(integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_mail_account"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_mail_account"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_mail_thread"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_mail_thread"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ingest_mail"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ingest_mail"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."link_mail_thread"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."link_mail_thread"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_mail_threads"(uuid, uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_mail_threads"(uuid, uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."log_mail_thread"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."mail_accounts_of"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mail_accounts_of"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mail_thread_visible"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mail_thread_visible"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mail_threads_of"(text, text, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mail_threads_of"(text, text, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."match_mail_thread"(uuid) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."record_sent_mail"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_sent_mail"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_mail_account_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_mail_account_status"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."store_mail_message"(uuid, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."unlink_mail_thread"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unlink_mail_thread"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_mail_account"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_mail_account"(uuid, text, boolean) TO "authenticated", "service_role";

GRANT SELECT ON TABLE "better_supabase"."mail_accounts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."mail_accounts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."mail_messages" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."mail_messages" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."mail_thread_subjects" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."mail_thread_subjects" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."mail_threads" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."mail_threads" TO "service_role";
