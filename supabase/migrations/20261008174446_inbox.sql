SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."chat_installations" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid,
  "adapter"        text                     NOT NULL,
  "external_id"    text                     NOT NULL,
  "credential_ref" jsonb,
  "metadata"       jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "installed_by"   uuid,
  "installed_at"   timestamp with time zone NOT NULL DEFAULT now(),
  "uninstalled_at" timestamp with time zone,
  CONSTRAINT "chat_installations_adapter_check" CHECK (((length(adapter) >= 1) AND (length(adapter) <= 100))),
  CONSTRAINT "chat_installations_adapter_external_id_key" UNIQUE (adapter, external_id),
  CONSTRAINT "chat_installations_credential_ref_check"
    CHECK (((credential_ref IS NULL) OR ((jsonb_typeof(credential_ref) = 'object'::text) AND (credential_ref ? 'provider'::text)))),
  CONSTRAINT "chat_installations_external_id_check" CHECK (((length(external_id) >= 1) AND (length(external_id) <= 500))),
  CONSTRAINT "chat_installations_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."chat_installations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."chat_state_cache" (
  "key_prefix" text                     NOT NULL,
  "cache_key"  text                     NOT NULL,
  "value"      jsonb                    NOT NULL,
  "expires_at" timestamp with time zone,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "chat_state_cache_pkey" PRIMARY KEY (key_prefix, cache_key)
);

ALTER TABLE "better_supabase"."chat_state_cache"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."chat_state_lists" (
  "id"         bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "key_prefix" text                     NOT NULL,
  "list_key"   text                     NOT NULL,
  "value"      jsonb                    NOT NULL,
  "expires_at" timestamp with time zone,
  CONSTRAINT "chat_state_lists_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."chat_state_lists"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."chat_state_locks" (
  "key_prefix" text                     NOT NULL,
  "thread_id"  text                     NOT NULL,
  "token"      text                     NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "chat_state_locks_pkey" PRIMARY KEY (key_prefix, thread_id)
);

ALTER TABLE "better_supabase"."chat_state_locks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."chat_state_queues" (
  "id"         bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "key_prefix" text                     NOT NULL,
  "thread_id"  text                     NOT NULL,
  "value"      jsonb                    NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  CONSTRAINT "chat_state_queues_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."chat_state_queues"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."chat_state_subscriptions" (
  "key_prefix" text                     NOT NULL,
  "thread_id"  text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "chat_state_subscriptions_pkey" PRIMARY KEY (key_prefix, thread_id)
);

ALTER TABLE "better_supabase"."chat_state_subscriptions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."contact_identities" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "contact_id"  uuid                     NOT NULL,
  "channel"     text                     NOT NULL,
  "external_id" text                     NOT NULL,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "contact_identities_channel_check" CHECK (((length(channel) >= 1) AND (length(channel) <= 50))),
  CONSTRAINT "contact_identities_external_id_check" CHECK (((length(external_id) >= 1) AND (length(external_id) <= 500))),
  CONSTRAINT "contact_identities_pkey" PRIMARY KEY (id),
  CONSTRAINT "contact_identities_tenant_id_channel_external_id_key" UNIQUE (tenant_id, channel, external_id)
);

ALTER TABLE "better_supabase"."contact_identities"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."contacts" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "user_id"    uuid,
  "name"       text,
  "email"      text,
  "phone"      text,
  "avatar_url" text,
  "metadata"   jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "contacts_email_check" CHECK ((length(email) <= 320)),
  CONSTRAINT "contacts_name_check" CHECK ((length(name) <= 200)),
  CONSTRAINT "contacts_phone_check" CHECK ((length(phone) <= 50)),
  CONSTRAINT "contacts_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."contacts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."conversation_events" (
  "id"              bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "tenant_id"       uuid                     NOT NULL,
  "conversation_id" uuid                     NOT NULL,
  "type"            text                     NOT NULL,
  "actor_id"        uuid,
  "data"            jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"      timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT "conversation_events_pkey" PRIMARY KEY (id),
  CONSTRAINT "conversation_events_type_check" CHECK ((type ~ '^[a-z][a-z0-9_]{0,40}$'::text))
);

ALTER TABLE "better_supabase"."conversation_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."conversation_participants" (
  "conversation_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "role"            text                     NOT NULL DEFAULT 'participant'::text,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "conversation_participants_pkey" PRIMARY KEY (conversation_id, user_id),
  CONSTRAINT "conversation_participants_role_check" CHECK ((role = ANY (ARRAY['participant'::text, 'watcher'::text])))
);

ALTER TABLE "better_supabase"."conversation_participants"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."conversation_reads" (
  "conversation_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "last_read_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "conversation_reads_pkey" PRIMARY KEY (conversation_id, user_id)
);

ALTER TABLE "better_supabase"."conversation_reads"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."conversations" (
  "id"                   uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"            uuid                     NOT NULL,
  "inbox_id"             uuid                     NOT NULL,
  "contact_id"           uuid                     NOT NULL,
  "subject"              text,
  "status"               text                     NOT NULL DEFAULT 'open'::text,
  "priority"             text                     NOT NULL DEFAULT 'normal'::text,
  "assignee_id"          uuid,
  "team_id"              uuid,
  "bot_mode"             text                     NOT NULL DEFAULT 'human'::text,
  "thread_id"            text,
  "snoozed_until"        timestamp with time zone,
  "last_message_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "last_message_preview" text,
  "first_response_at"    timestamp with time zone,
  "resolved_at"          timestamp with time zone,
  "metadata"             jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"           timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"           timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "conversations_bot_mode_check" CHECK ((bot_mode = ANY (ARRAY['bot'::text, 'human'::text, 'paused'::text]))),
  CONSTRAINT "conversations_pkey" PRIMARY KEY (id),
  CONSTRAINT "conversations_priority_check" CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text]))),
  CONSTRAINT "conversations_status_check" CHECK ((status = ANY (ARRAY['open'::text, 'pending'::text, 'snoozed'::text, 'resolved'::text]))),
  CONSTRAINT "conversations_subject_check" CHECK ((length(subject) <= 500))
);

ALTER TABLE "better_supabase"."conversations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."inbound_events" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid,
  "adapter"      text                     NOT NULL,
  "external_id"  text,
  "inbox_id"     uuid,
  "headers"      jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "body"         text                     NOT NULL,
  "status"       text                     NOT NULL DEFAULT 'received'::text,
  "error"        text,
  "attempts"     integer                  NOT NULL DEFAULT 0,
  "received_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "processed_at" timestamp with time zone,
  CONSTRAINT "inbound_events_adapter_check" CHECK (((length(adapter) >= 1) AND (length(adapter) <= 100))),
  CONSTRAINT "inbound_events_pkey" PRIMARY KEY (id),
  CONSTRAINT "inbound_events_status_check" CHECK ((status = ANY (ARRAY['received'::text, 'processed'::text, 'ignored'::text, 'failed'::text])))
);

ALTER TABLE "better_supabase"."inbound_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."inbox_members" (
  "inbox_id"   uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "role"       text                     NOT NULL DEFAULT 'agent'::text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inbox_members_pkey" PRIMARY KEY (inbox_id, user_id),
  CONSTRAINT "inbox_members_role_check" CHECK ((role = ANY (ARRAY['agent'::text, 'lead'::text])))
);

ALTER TABLE "better_supabase"."inbox_members"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."inbox_mentions" (
  "message_id" uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "tenant_id"  uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inbox_mentions_pkey" PRIMARY KEY (message_id, user_id)
);

ALTER TABLE "better_supabase"."inbox_mentions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."inbox_messages" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "conversation_id" uuid                     NOT NULL,
  "direction"       text                     NOT NULL,
  "kind"            text                     NOT NULL DEFAULT 'message'::text,
  "author_type"     text                     NOT NULL,
  "author_id"       uuid,
  "body"            text                     NOT NULL DEFAULT ''::text,
  "format"          text                     NOT NULL DEFAULT 'text'::text,
  "attachments"     jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "reactions"       jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "mentions"        uuid[]                   NOT NULL DEFAULT '{}'::uuid[],
  "external_id"     text,
  "reply_to"        uuid,
  "metadata"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"      timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "edited_at"       timestamp with time zone,
  "deleted_at"      timestamp with time zone,
  CONSTRAINT "inbox_messages_attachments_check" CHECK ((jsonb_typeof(attachments) = 'array'::text)),
  CONSTRAINT "inbox_messages_author_type_check" CHECK ((author_type = ANY (ARRAY['contact'::text, 'agent'::text, 'bot'::text, 'system'::text]))),
  CONSTRAINT "inbox_messages_body_check" CHECK ((length(body) <= 20000)),
  CONSTRAINT "inbox_messages_direction_check" CHECK ((direction = ANY (ARRAY['inbound'::text, 'outbound'::text]))),
  CONSTRAINT "inbox_messages_format_check" CHECK ((format = ANY (ARRAY['text'::text, 'markdown'::text]))),
  CONSTRAINT "inbox_messages_kind_check" CHECK ((kind = ANY (ARRAY['message'::text, 'note'::text]))),
  CONSTRAINT "inbox_messages_pkey" PRIMARY KEY (id),
  CONSTRAINT "inbox_messages_reactions_check" CHECK ((jsonb_typeof(reactions) = 'object'::text))
);

ALTER TABLE "better_supabase"."inbox_messages"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."inbox_team_members" (
  "team_id"    uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inbox_team_members_pkey" PRIMARY KEY (team_id, user_id)
);

ALTER TABLE "better_supabase"."inbox_team_members"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."inbox_teams" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid                     NOT NULL,
  "name"       text                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inbox_teams_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "inbox_teams_pkey" PRIMARY KEY (id),
  CONSTRAINT "inbox_teams_tenant_id_name_key" UNIQUE (tenant_id, name)
);

ALTER TABLE "better_supabase"."inbox_teams"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."inboxes" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"       uuid                     NOT NULL,
  "name"            text                     NOT NULL,
  "channel"         text                     NOT NULL DEFAULT 'in_app'::text,
  "channel_address" text,
  "installation_id" uuid,
  "bot_mode"        text                     NOT NULL DEFAULT 'human'::text,
  "settings"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "archived_at"     timestamp with time zone,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "inboxes_bot_mode_check" CHECK ((bot_mode = ANY (ARRAY['bot'::text, 'human'::text, 'paused'::text]))),
  CONSTRAINT "inboxes_channel_check"
    CHECK
    ((channel = ANY (ARRAY['in_app'::text, 'email'::text, 'slack'::text, 'teams'::text, 'discord'::text, 'telegram'::text, 'whatsapp'::text, 'messenger'::text, 'instagram'::text,
    'sms'::text, 'github'::text, 'linear'::text, 'other'::text]))),
  CONSTRAINT "inboxes_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "inboxes_pkey" PRIMARY KEY (id),
  CONSTRAINT "inboxes_settings_check" CHECK ((jsonb_typeof(settings) = 'object'::text))
);

ALTER TABLE "better_supabase"."inboxes"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."message_deliveries" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "message_id"  uuid                     NOT NULL,
  "channel"     text                     NOT NULL,
  "status"      text                     NOT NULL DEFAULT 'queued'::text,
  "external_id" text,
  "error"       text,
  "attempts"    integer                  NOT NULL DEFAULT 0,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "message_deliveries_message_id_channel_key" UNIQUE (message_id, channel),
  CONSTRAINT "message_deliveries_pkey" PRIMARY KEY (id),
  CONSTRAINT "message_deliveries_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'sent'::text, 'delivered'::text, 'read'::text, 'failed'::text])))
);

ALTER TABLE "better_supabase"."message_deliveries"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."message_templates" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid                     NOT NULL,
  "inbox_id"    uuid,
  "name"        text                     NOT NULL,
  "channel"     text                     NOT NULL,
  "language"    text                     NOT NULL DEFAULT 'en'::text,
  "body"        text                     NOT NULL,
  "variables"   jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "external_id" text,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "message_templates_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "message_templates_pkey" PRIMARY KEY (id),
  CONSTRAINT "message_templates_tenant_id_channel_name_language_key" UNIQUE (tenant_id, channel, name, LANGUAGE),
  CONSTRAINT "message_templates_variables_check" CHECK ((jsonb_typeof(variables) = 'array'::text))
);

ALTER TABLE "better_supabase"."message_templates"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."stream_chunks" (
  "stream_id" text    NOT NULL,
  "idx"       integer NOT NULL,
  "data"      text    NOT NULL,
  CONSTRAINT "stream_chunks_idx_check" CHECK ((idx >= 0)),
  CONSTRAINT "stream_chunks_pkey" PRIMARY KEY (stream_id, idx)
);

ALTER TABLE "better_supabase"."stream_chunks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."streams" (
  "id"                  text                     NOT NULL,
  "tenant_id"           uuid,
  "owner_id"            uuid,
  "kind"                text                     NOT NULL DEFAULT 'default'::text,
  "wake"                boolean                  NOT NULL DEFAULT true,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "closed_at"           timestamp with time zone,
  "cancel_requested_at" timestamp with time zone,
  "expires_at"          timestamp with time zone NOT NULL DEFAULT (now() + '1 day'::interval),
  CONSTRAINT "streams_id_check" CHECK (((length(id) >= 1) AND (length(id) <= 200))),
  CONSTRAINT "streams_kind_check" CHECK (((length(kind) >= 1) AND (length(kind) <= 100))),
  CONSTRAINT "streams_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."streams"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.assign_conversation (
  conversation uuid,
  assignee     uuid,
  team         uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."assign_conversation"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.create_inbox (
  tenant   uuid,
  name     text,
  channel  text  DEFAULT 'in_app'::text,
  settings jsonb DEFAULT '{}'::jsonb,
  bot_mode text  DEFAULT 'human'::text,
  address  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_inbox"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.create_inbox_team (
  tenant uuid,
  name   text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_inbox_team"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delete_message_template (
  template uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_message_template"($1) $function$;

CREATE OR REPLACE FUNCTION api.edit_message (
  message uuid,
  body    text    DEFAULT NULL::text,
  remove  boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."edit_message"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_conversation (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_conversation"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_message (
  message uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_message"($1) $function$;

CREATE OR REPLACE FUNCTION api.inbox_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."inbox_counts"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_conversation_events (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_conversation_events"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_conversations (
  tenant uuid  DEFAULT NULL::uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_conversations"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_messages (
  conversation uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max          integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_messages"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.mark_conversation_read (
  conversation uuid
)
  RETURNS timestamp WITH time zone
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_conversation_read"($1) $function$;

CREATE OR REPLACE FUNCTION api.pending_inbound_events (
  max          integer DEFAULT 100,
  max_attempts integer DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pending_inbound_events"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_contact (
  contact uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_contact"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_inbound_events (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_inbound_events"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.react_to_message (
  message uuid,
  emoji   text,
  present boolean DEFAULT true,
  actor   text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."react_to_message"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.record_delivery (
  message     uuid,
  channel     text,
  external_id text DEFAULT NULL::text,
  status      text DEFAULT 'sent'::text,
  error       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_delivery"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.record_inbound (
  input jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_inbound"($1) $function$;

CREATE OR REPLACE FUNCTION api.send_message (
  conversation uuid,
  input        jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."send_message"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.set_bot_mode (
  conversation uuid,
  mode         text,
  reason       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_bot_mode"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_conversation_status (
  conversation  uuid,
  status        text,
  snoozed_until timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_conversation_status"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_delivery_status (
  channel     text,
  external_id text,
  status      text,
  error       text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_delivery_status"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_inbound_event_status (
  event  uuid,
  status text,
  error  text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_inbound_event_status"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_inbox_member (
  inbox  uuid,
  member uuid,
  role   text DEFAULT 'agent'::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_inbox_member"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_inbox_team_member (
  team    uuid,
  member  uuid,
  present boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_inbox_team_member"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_typing (
  conversation uuid,
  typing       boolean DEFAULT true,
  actor        text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_typing"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.start_conversation (
  inbox uuid,
  input jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."start_conversation"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.store_inbound_event (
  adapter     text,
  body        text,
  external_id text  DEFAULT NULL::text,
  headers     jsonb DEFAULT '{}'::jsonb,
  inbox       uuid  DEFAULT NULL::uuid,
  tenant      uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."store_inbound_event"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.update_inbox (
  inbox uuid,
  patch jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_inbox"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.upsert_contact (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."upsert_contact"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.upsert_message_template (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."upsert_message_template"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.wake_snoozed_conversations()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."wake_snoozed_conversations"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.advance_schedule (
  job_name text,
  ran      timestamp with time zone,
  next_run timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select false;
$function$;

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
  v_conv "better_supabase"."conversations"%rowtype;
  v_before uuid;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = assign_conversation.conversation for update;
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
  update "better_supabase"."conversations" set
    "assignee_id" = assign_conversation.assignee,
    "team_id" = coalesce(assign_conversation.team, "team_id")
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from assignee then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'assigned', (select auth.uid()), jsonb_build_object('from', v_before, 'to', assign_conversation.assignee));
    
    if assignee is not null then
      insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", assignee)
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

CREATE OR REPLACE FUNCTION better_supabase.chat_install (
  adapter        text,
  external_id    text,
  tenant         uuid  DEFAULT NULL::uuid,
  credential_ref jsonb DEFAULT NULL::jsonb,
  installed_by   uuid  DEFAULT NULL::uuid,
  metadata       jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_previous jsonb;
  v_row "better_supabase"."chat_installations"%rowtype;
begin
  select "credential_ref" into v_previous from "better_supabase"."chat_installations"
  where "adapter" = chat_install.adapter and "external_id" = chat_install.external_id
  for update;
  insert into "better_supabase"."chat_installations" as i ("tenant_id", "adapter", "external_id", "credential_ref", "installed_by", "metadata")
  values (tenant, adapter, external_id, credential_ref, installed_by, coalesce(metadata, '{}'::jsonb))
  on conflict ("adapter", "external_id") do update
    set "tenant_id" = coalesce(excluded."tenant_id", i."tenant_id"),
        "credential_ref" = excluded."credential_ref",
        "installed_by" = coalesce(excluded."installed_by", i."installed_by"),
        "metadata" = i."metadata" || excluded."metadata",
        "installed_at" = clock_timestamp(),
        "uninstalled_at" = null
  returning * into v_row;
  return to_jsonb(v_row) || jsonb_build_object(
    'previous_credential_ref',
    case when v_previous is distinct from v_row."credential_ref" then v_previous end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_installation (
  adapter     text,
  external_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(i) from "better_supabase"."chat_installations" i
  where i."adapter" = chat_installation.adapter and i."external_id" = chat_installation.external_id;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_acquire_lock (
  prefix    text,
  thread_id text,
  token     text,
  ttl_ms    integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_lock "better_supabase"."chat_state_locks"%rowtype;
begin
  insert into "better_supabase"."chat_state_locks" as l ("key_prefix", "thread_id", "token", "expires_at")
  values (prefix, thread_id, token, clock_timestamp() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0))
  on conflict ("key_prefix", "thread_id") do update
    set "token" = excluded."token", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp()
    where l."expires_at" <= clock_timestamp()
  returning * into v_lock;
  if not found then
    return null;
  end if;
  return jsonb_build_object('thread_id', v_lock."thread_id", 'token', v_lock."token", 'expires_at', v_lock."expires_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_append_to_list (
  prefix     text,
  key        text,
  value      jsonb,
  max_length integer DEFAULT NULL::integer,
  ttl_ms     integer DEFAULT NULL::integer
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_expires timestamptz := case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end;
begin
  insert into "better_supabase"."chat_state_lists" ("key_prefix", "list_key", "value", "expires_at")
  values (prefix, key, value, v_expires);
  if max_length is not null and max_length > 0 then
    delete from "better_supabase"."chat_state_lists" l
    where l."key_prefix" = chat_state_append_to_list.prefix and l."list_key" = chat_state_append_to_list.key
      and l."id" < (
        select k."id" from "better_supabase"."chat_state_lists" k
        where k."key_prefix" = chat_state_append_to_list.prefix and k."list_key" = chat_state_append_to_list.key
        order by k."id" desc
        offset max_length - 1 limit 1
      );
  end if;
  update "better_supabase"."chat_state_lists" l set "expires_at" = v_expires
  where l."key_prefix" = chat_state_append_to_list.prefix and l."list_key" = chat_state_append_to_list.key
    and l."expires_at" is distinct from v_expires;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_delete (
  prefix text,
  key    text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  delete from "better_supabase"."chat_state_cache" c where c."key_prefix" = chat_state_delete.prefix and c."cache_key" = chat_state_delete.key;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_dequeue (
  prefix    text,
  thread_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_value jsonb;
begin
  delete from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_dequeue.prefix and q."thread_id" = chat_state_dequeue.thread_id
    and q."expires_at" <= clock_timestamp();
  delete from "better_supabase"."chat_state_queues" q
  where q."id" = (
    select k."id" from "better_supabase"."chat_state_queues" k
    where k."key_prefix" = chat_state_dequeue.prefix and k."thread_id" = chat_state_dequeue.thread_id
    order by k."id"
    limit 1
    for update skip locked
  )
  returning q."value" into v_value;
  return v_value;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_enqueue (
  prefix     text,
  thread_id  text,
  entry      jsonb,
  expires_at timestamp with time zone,
  max_size   integer                  DEFAULT NULL::integer
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_depth integer;
begin
  delete from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
    and q."expires_at" <= clock_timestamp();
  insert into "better_supabase"."chat_state_queues" ("key_prefix", "thread_id", "value", "expires_at")
  values (prefix, thread_id, entry, expires_at);
  if max_size is not null and max_size > 0 then
    delete from "better_supabase"."chat_state_queues" q
    where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
      and q."id" < (
        select k."id" from "better_supabase"."chat_state_queues" k
        where k."key_prefix" = chat_state_enqueue.prefix and k."thread_id" = chat_state_enqueue.thread_id
        order by k."id" desc
        offset max_size - 1 limit 1
      );
  end if;
  select count(*)::integer into v_depth from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_enqueue.prefix and q."thread_id" = chat_state_enqueue.thread_id
    and q."expires_at" > clock_timestamp();
  return v_depth;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_extend_lock (
  prefix    text,
  thread_id text,
  token     text,
  ttl_ms    integer
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."chat_state_locks" l
  set "expires_at" = clock_timestamp() + make_interval(secs => greatest(coalesce(ttl_ms, 0), 1) / 1000.0), "updated_at" = clock_timestamp()
  where l."key_prefix" = chat_state_extend_lock.prefix
    and l."thread_id" = chat_state_extend_lock.thread_id
    and l."token" = chat_state_extend_lock.token
    and l."expires_at" > clock_timestamp();
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_force_release_lock (
  prefix    text,
  thread_id text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."chat_state_locks" l
  where l."key_prefix" = chat_state_force_release_lock.prefix
    and l."thread_id" = chat_state_force_release_lock.thread_id;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_get (
  prefix text,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('value', c."value")
  from "better_supabase"."chat_state_cache" c
  where c."key_prefix" = chat_state_get.prefix and c."cache_key" = chat_state_get.key
    and (c."expires_at" is null or c."expires_at" > clock_timestamp());
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_get_list (
  prefix text,
  key    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(l."value" order by l."id"), '[]'::jsonb)
  from "better_supabase"."chat_state_lists" l
  where l."key_prefix" = chat_state_get_list.prefix and l."list_key" = chat_state_get_list.key
    and (l."expires_at" is null or l."expires_at" > clock_timestamp());
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_is_subscribed (
  prefix    text,
  thread_id text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select exists (select 1 from "better_supabase"."chat_state_subscriptions" s where s."key_prefix" = chat_state_is_subscribed.prefix and s."thread_id" = chat_state_is_subscribed.thread_id);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_queue_depth (
  prefix    text,
  thread_id text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  select count(*)::integer from "better_supabase"."chat_state_queues" q
  where q."key_prefix" = chat_state_queue_depth.prefix and q."thread_id" = chat_state_queue_depth.thread_id
    and q."expires_at" > clock_timestamp();
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_release_lock (
  prefix    text,
  thread_id text,
  token     text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  delete from "better_supabase"."chat_state_locks" l
  where l."key_prefix" = chat_state_release_lock.prefix
    and l."thread_id" = chat_state_release_lock.thread_id
    and l."token" = chat_state_release_lock.token;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_set (
  prefix text,
  key    text,
  value  jsonb,
  ttl_ms integer DEFAULT NULL::integer
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."chat_state_cache" ("key_prefix", "cache_key", "value", "expires_at")
  values (prefix, key, value, case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end)
  on conflict ("key_prefix", "cache_key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp();
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_set_if_not_exists (
  prefix text,
  key    text,
  value  jsonb,
  ttl_ms integer DEFAULT NULL::integer
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  insert into "better_supabase"."chat_state_cache" as c ("key_prefix", "cache_key", "value", "expires_at")
  values (prefix, key, value, case when ttl_ms is null or ttl_ms <= 0 then null else clock_timestamp() + make_interval(secs => ttl_ms / 1000.0) end)
  on conflict ("key_prefix", "cache_key") do update
    set "value" = excluded."value", "expires_at" = excluded."expires_at", "updated_at" = clock_timestamp()
    where c."expires_at" is not null and c."expires_at" <= clock_timestamp();
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_subscribe (
  prefix    text,
  thread_id text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."chat_state_subscriptions" ("key_prefix", "thread_id") values (prefix, thread_id)
  on conflict do nothing;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_state_unsubscribe (
  prefix    text,
  thread_id text
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  delete from "better_supabase"."chat_state_subscriptions" s where s."key_prefix" = chat_state_unsubscribe.prefix and s."thread_id" = chat_state_unsubscribe.thread_id;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.chat_uninstall (
  adapter     text,
  external_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_ref jsonb;
  v_row "better_supabase"."chat_installations"%rowtype;
begin
  select i."credential_ref" into v_ref from "better_supabase"."chat_installations" i
  where i."adapter" = chat_uninstall.adapter and i."external_id" = chat_uninstall.external_id
    and i."uninstalled_at" is null
  for update;
  if not found then
    return null;
  end if;
  update "better_supabase"."chat_installations" i set "uninstalled_at" = clock_timestamp(), "credential_ref" = null
  where i."adapter" = chat_uninstall.adapter and i."external_id" = chat_uninstall.external_id
  returning * into v_row;
  return to_jsonb(v_row) || jsonb_build_object('previous_credential_ref', v_ref);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_due_schedules (
  lease integer DEFAULT 60,
  batch integer DEFAULT 100
)
  RETURNS TABLE (
    job_name    text,
    schedule    text,
    timezone    text,
    queue       text,
    payload     jsonb,
    next_run    timestamp with time zone,
    first_after timestamp with time zone
  )
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select null::text, null::text, null::text, null::text, null::jsonb, null::timestamptz, null::timestamptz where false;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_jobs (
  queue text,
  lease integer DEFAULT 300,
  batch integer DEFAULT 1
)
  RETURNS TABLE (
    id            bigint,
    attempts      integer,
    enqueued_at   timestamp with time zone,
    visible_until timestamp with time zone,
    message       jsonb
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  r record;
begin
  perform better_supabase.ensure_job_queue(queue);
  for r in select * from pgmq.read(queue, lease, batch) loop
    if r.read_ct > coalesce((r.message ->> 'max_attempts')::integer, 5) then
      execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', ''The lease ran out on the last attempt'', ''dead'', true) where msg_id = $1', 'q_' || queue)
        using r.msg_id;
      perform pgmq.archive(queue, r.msg_id);
    else
      id := r.msg_id;
      attempts := r.read_ct;
      enqueued_at := r.enqueued_at;
      visible_until := r.vt;
      message := r.message;
      return next;
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_job (
  queue   text,
  job_id  bigint,
  attempt integer
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  hit bigint;
begin
  execute format('select msg_id from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into hit using job_id, attempt;
  if hit is null then
    return false;
  end if;
  return pgmq.archive(queue, job_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_inbox (
  tenant   uuid,
  name     text,
  channel  text  DEFAULT 'in_app'::text,
  settings jsonb DEFAULT '{}'::jsonb,
  bot_mode text  DEFAULT 'human'::text,
  address  text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inboxes"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_inbox.tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."inboxes" ("tenant_id", "name", "channel", "settings", "bot_mode", "channel_address")
  values (create_inbox.tenant, create_inbox.name, coalesce(create_inbox.channel, 'in_app'), coalesce(create_inbox.settings, '{}'::jsonb), coalesce(create_inbox.bot_mode, 'human'), create_inbox.address)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_inbox_team (
  tenant uuid,
  name   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inbox_teams"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_inbox_team.tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."inbox_teams" ("tenant_id", "name") values (create_inbox_team.tenant, create_inbox_team.name)
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_message_template (
  template uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."message_templates" where "id" = delete_message_template.template;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  delete from "better_supabase"."message_templates" t where t."id" = delete_message_template.template;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.edit_message (
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
  v_msg "better_supabase"."inbox_messages"%rowtype;
begin
  select * into v_msg from "better_supabase"."inbox_messages" where "id" = edit_message.message for update;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_msg."author_id" is not null and v_msg."author_id" = (select auth.uid()))) then
    raise exception 'only the author edits a message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if v_msg."deleted_at" is not null then
    raise exception 'message is deleted' using errcode = '22023', hint = 'MESSAGE_DELETED';
  end if;
  update "better_supabase"."inbox_messages" set
    "body" = case when coalesce(remove, false) then '' else coalesce(edit_message.body, "body") end,
    "attachments" = case when coalesce(remove, false) then '[]'::jsonb else "attachments" end,
    "deleted_at" = case when coalesce(remove, false) then now() end,
    "edited_at" = case when coalesce(remove, false) then "edited_at" else now() end
  where "id" = v_msg."id"
  returning * into v_msg;
  return to_jsonb(v_msg);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enqueue_job (
  queue          text,
  payload        jsonb   DEFAULT '{}'::jsonb,
  delay          integer DEFAULT 0,
  max_attempts   integer DEFAULT 5,
  dedupe_key     text    DEFAULT NULL::text,
  dedupe_running boolean DEFAULT true
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing bigint;
begin
  perform better_supabase.ensure_job_queue(queue);
  if dedupe_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
    execute format('select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 and ($2 or read_ct = 0) limit 1', 'q_' || queue)
      into existing using dedupe_key, dedupe_running;
    if existing is not null then
      return existing;
    end if;
  end if;
  return (
    select pgmq.send(
      queue,
      jsonb_build_object('payload', payload, 'max_attempts', max_attempts)
        || case when dedupe_key is null then '{}'::jsonb else jsonb_build_object('dedupe_key', dedupe_key) end,
      greatest(delay, 0)
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_job_queue (
  queue text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is null then
    perform pgmq.create(queue);
    perform better_supabase.index_job_queue(queue);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.extend_job_lease (
  queue   text,
  job_id  bigint,
  attempt integer,
  lease   integer
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  hit bigint;
begin
  execute format('select msg_id from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into hit using job_id, attempt;
  if hit is null then
    return false;
  end if;
  perform pgmq.set_vt(queue, job_id, lease);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fail_job (
  queue    text,
  job_id   bigint,
  attempt  integer,
  error    text,
  retry_in integer DEFAULT NULL::integer
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  msg jsonb;
begin
  execute format('select message from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into msg using job_id, attempt;
  if msg is null then
    return null;
  end if;
  if attempt >= coalesce((msg ->> 'max_attempts')::integer, 5) then
    execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text, ''dead'', true) where msg_id = $1', 'q_' || queue)
      using job_id, left(error, 4000);
    perform pgmq.archive(queue, job_id);
    return 'dead';
  end if;
  execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text), vt = clock_timestamp() + make_interval(secs => $3) where msg_id = $1', 'q_' || queue)
    using job_id, left(error, 4000), coalesce(retry_in, 1 + floor(random() * least(3600, 10 * power(2, attempt - 1)))::integer);
  return 'queued';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_conversation (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select "better_supabase"."inbox_conversation_json"(v."id") from "better_supabase"."conversations" v where v."id" = conversation;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_message (
  message uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(m) || jsonb_build_object('delivery', (
    select jsonb_build_object('status', d."status", 'channel', d."channel", 'error', d."error", 'updated_at', d."updated_at")
    from "better_supabase"."message_deliveries" d where d."message_id" = m."id"
    order by d."created_at" limit 1
  ))
  from "better_supabase"."inbox_messages" m where m."id" = get_message.message;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_add_message (
  conversation uuid,
  input        jsonb,
  author_type  text,
  author       uuid,
  direction    text
)
  RETURNS better_supabase.inbox_messages
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_inbox "better_supabase"."inboxes"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_kind text := coalesce(input ->> 'kind', 'message');
  v_mentions uuid[];
  v_reopened boolean := false;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = inbox_add_message.conversation for update;
  select * into v_inbox from "better_supabase"."inboxes" where "id" = v_conv."inbox_id";
  if input ? 'external_id' then
    select * into v_msg from "better_supabase"."inbox_messages" m
    where m."conversation_id" = v_conv."id" and m."external_id" = input ->> 'external_id';
    if found then
      return v_msg;
    end if;
  end if;
  if length(btrim(coalesce(input ->> 'body', ''))) = 0 and coalesce(jsonb_array_length(input -> 'attachments'), 0) = 0 then
    raise exception 'a message needs a body or an attachment' using errcode = '22023', hint = 'INBOX_MESSAGE_EMPTY';
  end if;
  select coalesce(array_agg(distinct x), '{}') into v_mentions
  from jsonb_array_elements_text(coalesce(input -> 'mentions', '[]'::jsonb)) e(raw)
  cross join lateral (select e.raw::uuid as x) u
  where coalesce(better_supabase.can_user(u.x, 'tenant', v_conv."tenant_id", 'inbox.read'), false);
  insert into "better_supabase"."inbox_messages" ("tenant_id", "conversation_id", "direction", "kind", "author_type", "author_id", "body", "format", "attachments", "mentions", "external_id", "reply_to", "metadata")
  values (
    v_conv."tenant_id", v_conv."id", inbox_add_message.direction, v_kind, inbox_add_message.author_type, inbox_add_message.author,
    coalesce(input ->> 'body', ''), coalesce(input ->> 'format', 'text'), coalesce(input -> 'attachments', '[]'::jsonb), v_mentions,
    input ->> 'external_id', (input ->> 'reply_to')::uuid, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_msg;
  insert into "better_supabase"."inbox_mentions" ("message_id", "user_id", "tenant_id")
  select v_msg."id", x, v_msg."tenant_id" from unnest(v_mentions) x
  on conflict do nothing;
  if v_kind = 'message' then
    v_reopened := inbox_add_message.direction = 'inbound' and v_conv."status" in ('resolved', 'snoozed');
    update "better_supabase"."conversations" set
      "last_message_at" = v_msg."created_at",
      "last_message_preview" = left(v_msg."body", 140),
      "first_response_at" = case
        when "first_response_at" is null and inbox_add_message.direction = 'outbound' and inbox_add_message.author_type in ('agent', 'bot') then v_msg."created_at"
        else "first_response_at" end,
      "status" = case when v_reopened then 'open' else "status" end,
      "snoozed_until" = case when v_reopened then null else "snoozed_until" end,
      "resolved_at" = case when v_reopened then null else "resolved_at" end
    where "id" = v_conv."id"
    returning * into v_conv;
    if v_reopened then
      insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'reopened', (select auth.uid()), jsonb_build_object('by', 'contact'));
      
    end if;
  end if;
  if inbox_add_message.author is not null and inbox_add_message.author_type = 'agent' then
    insert into "better_supabase"."conversation_participants" ("conversation_id", "user_id") values (v_conv."id", inbox_add_message.author)
    on conflict do nothing;
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'inbound' then
    
    if v_conv."bot_mode" = 'bot' then
      perform "better_supabase"."enqueue_job"('inbox_bot', jsonb_build_object('conversation_id', v_conv."id", 'message_id', v_msg."id", 'thread_id', v_conv."thread_id", 'inbox_id', v_conv."inbox_id"), 0, 5, 'inbox:' || v_conv."id"::text, false);
    end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inbox.message',
      'tenant', v_conv."tenant_id",
      'subject_type', 'conversation',
      'subject_id', v_conv."id"::text,
      'summary', left(v_msg."body", 140),
      'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
      'key', 'inbox.message:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if v_kind = 'message' and inbox_add_message.direction = 'outbound' and v_inbox."channel" <> 'in_app' then
    insert into "better_supabase"."message_deliveries" ("tenant_id", "message_id", "channel")
    values (v_msg."tenant_id", v_msg."id", v_inbox."channel")
    on conflict do nothing;
    if not coalesce((input ->> 'delivered_by_caller')::boolean, false) then
      perform "better_supabase"."enqueue_job"('inbox_outbound', jsonb_build_object('message_id', v_msg."id", 'conversation_id', v_conv."id", 'inbox_id', v_conv."inbox_id"), 0, 5, 'inbox-out:' || v_msg."id"::text, false);
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
      'summary', left(v_msg."body", 140),
      'recipients', to_jsonb(v_mentions),
      'key', 'inbox.mention:' || v_msg."id"::text,
      'data', jsonb_build_object('conversationId', v_conv."id", 'messageId', v_msg."id")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  return v_msg;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_contact_conversation_ids()
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select v."id" from "better_supabase"."conversations" v
  join "better_supabase"."contacts" c on c."id" = v."contact_id"
  where c."user_id" = (select auth.uid());
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_contact_ids()
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select c."id" from "better_supabase"."contacts" c where c."user_id" = (select auth.uid());
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
  select coalesce((
    select (case when write then coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.reply'), false) else coalesce(better_supabase.can('tenant', v."tenant_id", 'inbox.read'), false) end)
      or exists (select 1 from "better_supabase"."contacts" c where c."id" = v."contact_id" and c."user_id" = (select auth.uid()))
    from "better_supabase"."conversations" v
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
    perform realtime.send(v_payload, 'conversation', 'inbox:' || new."id"::text, true);
    perform realtime.send(v_payload, 'conversation', 'inbox:org:' || new."tenant_id"::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_conversation_json (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(v) || jsonb_build_object(
    'contact', (select jsonb_build_object('id', c."id", 'name', c."name", 'email', c."email", 'phone', c."phone", 'avatar_url', c."avatar_url", 'user_id', c."user_id") from "better_supabase"."contacts" c where c."id" = v."contact_id"),
    'inbox', (select jsonb_build_object('id', i."id", 'name', i."name", 'channel', i."channel") from "better_supabase"."inboxes" i where i."id" = v."inbox_id"),
    'last_read_at', (select r."last_read_at" from "better_supabase"."conversation_reads" r where r."conversation_id" = v."id" and r."user_id" = (select auth.uid()))
  )
  from "better_supabase"."conversations" v
  where v."id" = conversation;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_counts (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'open', count(*),
    'mine', count(*) filter (where v."assignee_id" = (select auth.uid())),
    'unassigned', count(*) filter (where v."assignee_id" is null),
    'unread', count(*) filter (where v."last_message_at" > coalesce(r."last_read_at", '-infinity'::timestamptz)
      and (v."assignee_id" is null or v."assignee_id" = (select auth.uid())))
  )
  from "better_supabase"."conversations" v
  left join "better_supabase"."conversation_reads" r on r."conversation_id" = v."id" and r."user_id" = (select auth.uid())
  where v."tenant_id" = inbox_counts.tenant and v."status" = 'open';
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
      jsonb_build_object('conversation_id', m."conversation_id", 'message_id', new."message_id", 'status', new."status"),
      'delivery',
      'inbox:org:' || new."tenant_id"::text,
      true
    )
    from "better_supabase"."inbox_messages" m where m."id" = new."message_id";
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_file_allowed (
  object_name text,
  write       boolean DEFAULT false
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce((
    select "better_supabase"."inbox_conversation_allowed"(v."id"::text, write)
    from "better_supabase"."conversations" v
    where v."tenant_id"::text = split_part(object_name, '/', 1)
      and v."id"::text = split_part(object_name, '/', 2)
  ), false);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_message_broadcast()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_payload jsonb := jsonb_build_object('conversation_id', new."conversation_id", 'message_id', new."id", 'kind', new."kind");
  v_event text := case when tg_op = 'INSERT' then 'message' else 'message_updated' end;
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    if new."kind" = 'message' then
      perform realtime.send(v_payload, v_event, 'inbox:' || new."conversation_id"::text, true);
    end if;
    perform realtime.send(v_payload, v_event, 'inbox:org:' || new."tenant_id"::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inbox_resolve_contact (
  tenant uuid,
  input  jsonb
)
  RETURNS better_supabase.contacts
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_contact "better_supabase"."contacts"%rowtype;
  v_identity jsonb := input -> 'identity';
begin
  if input ? 'id' then
    select * into v_contact from "better_supabase"."contacts" c where c."id" = (input ->> 'id')::uuid and c."tenant_id" = inbox_resolve_contact.tenant;
    if not found then
      raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
    end if;
  end if;
  if v_contact."id" is null and v_identity is not null then
    select c.* into v_contact from "better_supabase"."contact_identities" i join "better_supabase"."contacts" c on c."id" = i."contact_id"
    where i."tenant_id" = inbox_resolve_contact.tenant and i."channel" = v_identity ->> 'channel' and i."external_id" = v_identity ->> 'external_id';
  end if;
  if v_contact."id" is null and input ? 'user_id' then
    select * into v_contact from "better_supabase"."contacts" c where c."tenant_id" = inbox_resolve_contact.tenant and c."user_id" = (input ->> 'user_id')::uuid;
  end if;
  if v_contact."id" is null and nullif(input ->> 'email', '') is not null then
    select * into v_contact from "better_supabase"."contacts" c where c."tenant_id" = inbox_resolve_contact.tenant and lower(c."email") = lower(input ->> 'email')
    order by c."created_at" limit 1;
  end if;
  if v_contact."id" is null then
    insert into "better_supabase"."contacts" ("tenant_id", "user_id", "name", "email", "phone", "avatar_url", "metadata")
    values (inbox_resolve_contact.tenant, (input ->> 'user_id')::uuid, input ->> 'name', input ->> 'email', input ->> 'phone', input ->> 'avatar_url', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_contact;
  else
    update "better_supabase"."contacts" c set
      "name" = coalesce(c."name", input ->> 'name'),
      "email" = coalesce(c."email", input ->> 'email'),
      "phone" = coalesce(c."phone", input ->> 'phone'),
      "avatar_url" = coalesce(input ->> 'avatar_url', c."avatar_url"),
      "user_id" = coalesce(c."user_id", (input ->> 'user_id')::uuid),
      "metadata" = c."metadata" || coalesce(input -> 'metadata', '{}'::jsonb)
    where c."id" = v_contact."id"
    returning * into v_contact;
  end if;
  if v_identity is not null and v_identity ? 'channel' and v_identity ? 'external_id' then
    insert into "better_supabase"."contact_identities" ("tenant_id", "contact_id", "channel", "external_id")
    values (inbox_resolve_contact.tenant, v_contact."id", v_identity ->> 'channel', v_identity ->> 'external_id')
    on conflict do nothing;
  end if;
  return v_contact;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.index_job_queue (
  queue text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  execute format(
    'create index if not exists %I on pgmq.%I ((message ->> ''dedupe_key'')) where message ? ''dedupe_key''',
    'q_' || queue || '_dedupe_idx',
    'q_' || queue
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.job_queue_stats (
  queue text
)
  RETURNS TABLE (
    ready              bigint,
    in_flight          bigint,
    delayed            bigint,
    dead               bigint,
    oldest_age_seconds double precision
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is null then
    return query select 0::bigint, 0::bigint, 0::bigint, 0::bigint, null::double precision;
    return;
  end if;
  return query execute format(
    'select count(*) filter (where q.vt <= clock_timestamp()),
       count(*) filter (where q.vt > clock_timestamp() and q.read_ct > 0),
       count(*) filter (where q.vt > clock_timestamp() and q.read_ct = 0),
       (select count(*) from pgmq.%2$I a where a.message ? ''dead''),
       extract(epoch from clock_timestamp() - min(q.enqueued_at))::double precision
     from pgmq.%1$I q',
    'q_' || queue, 'a_' || queue
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_chat_installations (
  tenant              uuid    DEFAULT NULL::uuid,
  adapter             text    DEFAULT NULL::text,
  include_uninstalled boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(i) order by i."installed_at" desc), '[]'::jsonb)
  from "better_supabase"."chat_installations" i
  where (list_chat_installations.tenant is null or i."tenant_id" = list_chat_installations.tenant)
    and (list_chat_installations.adapter is null or i."adapter" = list_chat_installations.adapter)
    and (coalesce(include_uninstalled, false) or i."uninstalled_at" is null);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_conversation_events (
  conversation uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(e) order by e."id"), '[]'::jsonb)
  from "better_supabase"."conversation_events" e where e."conversation_id" = list_conversation_events.conversation;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_conversations (
  tenant uuid  DEFAULT NULL::uuid,
  filter jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg("better_supabase"."inbox_conversation_json"(page."id") || jsonb_build_object('unread', page.unread) order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
  from (
    select v."id", v."last_message_at",
      v."last_message_at" > coalesce((select r."last_read_at" from "better_supabase"."conversation_reads" r where r."conversation_id" = v."id" and r."user_id" = (select auth.uid())), '-infinity'::timestamptz) as unread
    from "better_supabase"."conversations" v
    left join "better_supabase"."contacts" c on c."id" = v."contact_id"
    where (list_conversations.tenant is null or v."tenant_id" = list_conversations.tenant)
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
  ) page;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_dead_jobs (
  queue     text,
  max_rows  integer DEFAULT 100,
  before_id bigint  DEFAULT NULL::bigint
)
  RETURNS TABLE (
    id          bigint,
    attempts    integer,
    enqueued_at timestamp with time zone,
    died_at     timestamp with time zone,
    message     jsonb
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'a_' || queue)) is null then
    return;
  end if;
  return query execute format(
    'select a.msg_id, a.read_ct, a.enqueued_at, a.archived_at, a.message from pgmq.%I a
     where a.message ? ''dead'' and ($2 is null or a.msg_id < $2)
     order by a.msg_id desc limit least(greatest($1, 1), 1000)',
    'a_' || queue
  ) using max_rows, before_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_messages (
  conversation uuid,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max          integer                  DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(page.item order by page.created_at, page.id), '[]'::jsonb)
  from (
    select m."created_at" as created_at, m."id" as id,
      to_jsonb(m) || jsonb_build_object('delivery', (
        select jsonb_build_object('status', d."status", 'channel', d."channel", 'error', d."error", 'updated_at', d."updated_at")
        from "better_supabase"."message_deliveries" d where d."message_id" = m."id"
        order by d."created_at" limit 1
      )) as item
    from "better_supabase"."inbox_messages" m
    where m."conversation_id" = list_messages.conversation
      and (before is null or m."created_at" < before)
    order by m."created_at" desc, m."id" desc
    limit least(greatest(coalesce(max, 50), 1), 200)
  ) page;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_schedules (
  name_prefix text DEFAULT NULL::text,
  for_tenant  text DEFAULT NULL::text
)
  RETURNS TABLE (
    job_name     text,
    schedule     text,
    timezone     text,
    queue        text,
    tenant       text,
    next_run     timestamp with time zone,
    last_run     timestamp with time zone,
    locked_until timestamp with time zone,
    created_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regnamespace('cron') is null or list_schedules.for_tenant is not null then
    return;
  end if;
  return query execute
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz
     from cron.job j where $1 is null or starts_with(j.jobname, $1) order by j.jobname'
    using name_prefix;
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
begin
  if (select auth.uid()) is null or not "better_supabase"."inbox_conversation_allowed"(conversation::text) then
    raise exception 'not allowed to read this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."conversation_reads" ("conversation_id", "user_id", "last_read_at")
  values (conversation, (select auth.uid()), v_at)
  on conflict ("conversation_id", "user_id") do update set "last_read_at" = excluded."last_read_at";
  return v_at;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pending_inbound_events (
  max          integer DEFAULT 100,
  max_attempts integer DEFAULT 5
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(to_jsonb(e) order by e."received_at"), '[]'::jsonb)
  from (
    select * from "better_supabase"."inbound_events" x
    where x."status" in ('received', 'failed') and x."attempts" < coalesce(max_attempts, 5)
    order by x."received_at"
    limit least(greatest(coalesce(max, 100), 1), 1000)
  ) e;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_chat_state (
  batch integer DEFAULT 5000
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_limit integer := greatest(coalesce(batch, 5000), 1);
  v_count integer := 0;
  v_rows integer;
begin
  delete from "better_supabase"."chat_state_locks" l where ctid in (select ctid from "better_supabase"."chat_state_locks" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."chat_state_cache" c where ctid in (select ctid from "better_supabase"."chat_state_cache" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."chat_state_lists" l where l."id" in (select "id" from "better_supabase"."chat_state_lists" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;
  delete from "better_supabase"."chat_state_queues" q where q."id" in (select "id" from "better_supabase"."chat_state_queues" where "expires_at" <= clock_timestamp() limit v_limit);
  get diagnostics v_rows = row_count;
  return v_count + v_rows;
end;
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
  v_conversations integer;
  v_messages integer;
  v_paths jsonb;
begin
  select c."tenant_id" into v_tenant from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  if not found then
    raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to erase contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  select count(*)::integer into v_conversations from "better_supabase"."conversations" v where v."contact_id" = purge_contact.contact;
  select coalesce(jsonb_agg(a ->> 'path') filter (where a ? 'path'), '[]'::jsonb)
  into v_paths
  from "better_supabase"."inbox_messages" m
  join "better_supabase"."conversations" v on v."id" = m."conversation_id"
  left join lateral jsonb_array_elements(m."attachments") a on true
  where v."contact_id" = purge_contact.contact;
  select count(*)::integer into v_messages
  from "better_supabase"."inbox_messages" m
  join "better_supabase"."conversations" v on v."id" = m."conversation_id"
  where v."contact_id" = purge_contact.contact;
  delete from "better_supabase"."contacts" c where c."id" = purge_contact.contact;
  return jsonb_build_object('conversations', v_conversations, 'messages', v_messages, 'attachments', v_paths);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_inbound_events (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."inbound_events" e where e."id" in (
    select x."id" from "better_supabase"."inbound_events" x
    where x."received_at" < now() - coalesce(older_than, interval '30 days')
      and x."status" in ('processed', 'ignored')
    limit greatest(coalesce(batch, 1000), 1)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_job_archive (
  queue           text,
  older_than      interval DEFAULT '7 days'::interval,
  batch           integer  DEFAULT 10000,
  dead_older_than interval DEFAULT '30 days'::interval
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  purged integer;
begin
  execute format(
    'with purged as (delete from pgmq.%1$I where msg_id in (select a.msg_id from pgmq.%1$I a where a.archived_at < now() - case when a.message ? ''dead'' then $3 else $1 end order by a.msg_id limit $2) returning 1) select count(*)::integer from purged',
    'a_' || queue
  ) into purged using older_than, batch, dead_older_than;
  return purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_streams (
  older_than interval DEFAULT '1 day'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_count integer;
begin
  with doomed as (
    select "id" from "better_supabase"."streams"
    where "expires_at" <= now()
      or "closed_at" <= now() - coalesce(older_than, interval '1 day')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."streams" st using doomed where st."id" = doomed."id";
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.react_to_message (
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
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_who text;
begin
  select * into v_msg from "better_supabase"."inbox_messages" where "id" = react_to_message.message for update;
  if not found then
    raise exception 'message not found' using errcode = 'P0002', hint = 'MESSAGE_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_who := coalesce(actor, 'bot');
  elsif v_msg."kind" = 'message' and "better_supabase"."inbox_conversation_allowed"(v_msg."conversation_id"::text, true) then
    v_who := (select auth.uid())::text;
  elsif v_msg."kind" = 'note' and coalesce(better_supabase.can('tenant', v_msg."tenant_id", 'inbox.reply'), false) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to react to this message' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if length(emoji) not between 1 and 64 then
    raise exception 'emoji must be 1 to 64 characters' using errcode = '22023', hint = 'INBOX_REACTION_INVALID';
  end if;
  update "better_supabase"."inbox_messages" set "reactions" = case
    when coalesce(present, true) then
      "reactions" || jsonb_build_object(emoji, (
        select coalesce(jsonb_agg(distinct x), '[]'::jsonb)
        from jsonb_array_elements_text(coalesce("reactions" -> emoji, '[]'::jsonb) || to_jsonb(v_who)) x
      ))
    else
      case when (select count(*) from jsonb_array_elements_text(coalesce("reactions" -> emoji, '[]'::jsonb)) x where x <> v_who) = 0
        then "reactions" - emoji
        else "reactions" || jsonb_build_object(emoji, (select jsonb_agg(x) from jsonb_array_elements_text("reactions" -> emoji) x where x <> v_who))
      end
    end
  where "id" = v_msg."id"
  returning * into v_msg;
  return v_msg."reactions";
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
  select m."tenant_id", m."id", record_delivery.channel, record_delivery.external_id, coalesce(record_delivery.status, 'sent'), record_delivery.error, 1
  from "better_supabase"."inbox_messages" m where m."id" = record_delivery.message
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
  v_conv "better_supabase"."conversations"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_created boolean := false;
  v_duplicate boolean := false;
  v_message jsonb := coalesce(input -> 'message', '{}'::jsonb);
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = (input ->> 'inbox_id')::uuid;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if v_contact_input ? 'external_id' and not v_contact_input ? 'identity' then
    v_contact_input := v_contact_input || jsonb_build_object('identity', jsonb_build_object('channel', coalesce(v_contact_input ->> 'channel', v_inbox."channel"), 'external_id', v_contact_input ->> 'external_id'));
  end if;
  select * into v_conv from "better_supabase"."conversations"
  where "inbox_id" = v_inbox."id" and "thread_id" = input ->> 'thread_id'
  for update;
  if not found then
    v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
    insert into "better_supabase"."conversations" ("tenant_id", "inbox_id", "contact_id", "subject", "bot_mode", "thread_id", "metadata")
    values (v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', v_inbox."bot_mode", input ->> 'thread_id', coalesce(input -> 'metadata', '{}'::jsonb))
    returning * into v_conv;
    v_created := true;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), jsonb_build_object('by', 'channel'));
    
  end if;
  if v_message ? 'external_id' then
    v_duplicate := exists (select 1 from "better_supabase"."inbox_messages" m where m."conversation_id" = v_conv."id" and m."external_id" = v_message ->> 'external_id');
  end if;
  v_msg := "better_supabase"."inbox_add_message"(
    v_conv."id",
    v_message - 'kind',
    case when coalesce(input ->> 'direction', 'inbound') = 'inbound' then 'contact' else coalesce(input ->> 'author_type', 'bot') end,
    null,
    coalesce(input ->> 'direction', 'inbound')
  );
  return jsonb_build_object(
    'conversation_id', v_conv."id",
    'message_id', v_msg."id",
    'contact_id', v_conv."contact_id",
    'tenant_id', v_conv."tenant_id",
    'created', v_created,
    'duplicate', v_duplicate
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.replay_dead_job (
  queue  text,
  job_id bigint
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  msg jsonb;
begin
  perform better_supabase.ensure_job_queue(queue);
  execute format('delete from pgmq.%I where msg_id = $1 and message ? ''dead'' returning message', 'a_' || queue)
    into msg using job_id;
  if msg is null then
    return null;
  end if;
  return better_supabase.enqueue_job(
    queue,
    coalesce(msg -> 'payload', '{}'),
    0,
    coalesce((msg ->> 'max_attempts')::integer, 5),
    msg ->> 'dedupe_key'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.retry_dead_jobs (
  queue text,
  ids   bigint[] DEFAULT NULL::bigint[],
  batch integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  dead_id bigint;
  retried integer := 0;
begin
  for dead_id in
    select d.id from better_supabase.list_dead_jobs(queue, batch) d where ids is null
    union all
    select unnest(ids) where ids is not null
  loop
    if better_supabase.replay_dead_job(queue, dead_id) is not null then
      retried := retried + 1;
    end if;
  end loop;
  return retried;
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
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read',
      'inbox.read', 'inbox.reply', 'inbox.assign', 'inbox.manage'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read', 'inbox.read', 'inbox.reply'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_job (
  job_name text,
  schedule text,
  queue    text,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  next_run timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  tenant   text                     DEFAULT NULL::text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set sql.modules.jobs.options.scheduler to "drain" to keep one per schedule';
  end if;
  if pg_catalog.to_regnamespace('cron') is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set sql.modules.jobs.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set sql.modules.jobs.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;
  perform better_supabase.ensure_job_queue(queue);
  return cron.schedule(job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.send_message (
  conversation uuid,
  input        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_msg "better_supabase"."inbox_messages"%rowtype;
  v_author_type text;
  v_direction text;
  v_kind text := coalesce(input ->> 'kind', 'message');
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = send_message.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_author_type := coalesce(input ->> 'author_type', 'bot');
    v_direction := case when v_author_type = 'contact' then 'inbound' else 'outbound' end;
  elsif coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false) then
    v_author_type := 'agent';
    v_direction := 'outbound';
  elsif exists (select 1 from "better_supabase"."contacts" c where c."id" = v_conv."contact_id" and c."user_id" = (select auth.uid())) then
    if v_kind <> 'message' then
      raise exception 'contacts cannot write notes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
    end if;
    v_author_type := 'contact';
    v_direction := 'inbound';
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_msg := "better_supabase"."inbox_add_message"(v_conv."id", coalesce(input, '{}'::jsonb) - 'author_type', v_author_type, (select auth.uid()), v_direction);
  if v_author_type = 'agent' and v_kind = 'message' and v_conv."bot_mode" = 'bot' then
    update "better_supabase"."conversations" set "bot_mode" = 'human' where "id" = v_conv."id" returning * into v_conv;
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', 'bot', 'to', 'human', 'reason', 'agent_reply'));
  end if;
  return to_jsonb(v_msg);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_bot_mode (
  conversation uuid,
  mode         text,
  reason       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before text;
  v_claims text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = set_bot_mode.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_before := v_conv."bot_mode";
  update "better_supabase"."conversations" set "bot_mode" = mode where "id" = v_conv."id" returning * into v_conv;
  if v_before is distinct from mode then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'handoff', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_bot_mode.mode, 'reason', set_bot_mode.reason));
    if v_before = 'bot' and mode = 'human' then
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inbox.handoff',
        'tenant', v_conv."tenant_id",
        'actor', (select auth.uid()),
        'subject_type', 'conversation',
        'subject_id', v_conv."id"::text,
        'summary', coalesce(set_bot_mode.reason, v_conv."last_message_preview"),
        'recipients', case when v_conv."assignee_id" is not null then to_jsonb(array[v_conv."assignee_id"])
    else coalesce((select jsonb_agg(m."user_id") from "better_supabase"."inbox_members" m where m."inbox_id" = v_conv."inbox_id"), '[]'::jsonb) end,
        'key', 'inbox.handoff:' || v_conv."id"::text || ':' || extract(epoch from now())::text,
        'data', jsonb_build_object('conversationId', v_conv."id", 'reason', set_bot_mode.reason)
      ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      null;
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_conversation_status (
  conversation  uuid,
  status        text,
  snoozed_until timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations"%rowtype;
  v_before text;
begin
  select * into v_conv from "better_supabase"."conversations" where "id" = set_conversation_status.conversation for update;
  if not found then
    raise exception 'conversation not found' using errcode = 'P0002', hint = 'CONVERSATION_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_conv."tenant_id", 'inbox.reply'), false)) then
    raise exception 'not allowed to change this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if status = 'snoozed' and snoozed_until is null then
    raise exception 'snoozing needs snoozed_until' using errcode = '22023', hint = 'INBOX_SNOOZE_UNTIL';
  end if;
  v_before := v_conv."status";
  update "better_supabase"."conversations" set
    "status" = set_conversation_status.status,
    "snoozed_until" = case when set_conversation_status.status = 'snoozed' then set_conversation_status.snoozed_until end,
    "resolved_at" = case when set_conversation_status.status = 'resolved' then now() end
  where "id" = v_conv."id"
  returning * into v_conv;
  if v_before is distinct from status then
    insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'status', (select auth.uid()), jsonb_build_object('from', v_before, 'to', set_conversation_status.status));
    if status = 'resolved' then
      
    elsif v_before = 'resolved' then
      
    end if;
  end if;
  return "better_supabase"."inbox_conversation_json"(v_conv."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_delivery_status (
  channel     text,
  external_id text,
  status      text,
  error       text DEFAULT NULL::text
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_count integer;
begin
  update "better_supabase"."message_deliveries" d set "status" = status, "error" = coalesce(error, d."error")
  where d."channel" = channel and d."external_id" = external_id
    and (case status when 'failed' then d."status" in ('queued', 'sent')
      else array_position(array['queued', 'sent', 'delivered', 'read'], status)
        > coalesce(array_position(array['queued', 'sent', 'delivered', 'read'], d."status"), 0) end);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_inbound_event_status (
  event  uuid,
  status text,
  error  text DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."inbound_events" e set
    "status" = status,
    "error" = error,
    "attempts" = e."attempts" + 1,
    "processed_at" = case when status in ('processed', 'ignored') then now() else e."processed_at" end
  where e."id" = event;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_inbox_member (
  inbox  uuid,
  member uuid,
  role   text DEFAULT 'agent'::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."inboxes" where "id" = set_inbox_member.inbox;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if role is null then
    delete from "better_supabase"."inbox_members" m where m."inbox_id" = set_inbox_member.inbox and m."user_id" = member;
    return found;
  end if;
  if not coalesce(better_supabase.can_user(member, 'tenant', v_tenant, 'inbox.read'), false) then
    raise exception 'user cannot read this inbox' using errcode = '22023', hint = 'INBOX_MEMBER_INVALID';
  end if;
  insert into "better_supabase"."inbox_members" ("inbox_id", "user_id", "role") values (set_inbox_member.inbox, member, role)
  on conflict ("inbox_id", "user_id") do update set "role" = excluded."role";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_inbox_team_member (
  team    uuid,
  member  uuid,
  present boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select "tenant_id" into v_tenant from "better_supabase"."inbox_teams" where "id" = set_inbox_team_member.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'INBOX_TEAM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  if not coalesce(present, true) then
    delete from "better_supabase"."inbox_team_members" t where t."team_id" = set_inbox_team_member.team and t."user_id" = member;
    return found;
  end if;
  insert into "better_supabase"."inbox_team_members" ("team_id", "user_id") values (set_inbox_team_member.team, member)
  on conflict do nothing;
  return true;
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
    v_who := coalesce(actor, 'bot');
  elsif "better_supabase"."inbox_conversation_allowed"(conversation::text, true) then
    v_who := (select auth.uid())::text;
  else
    raise exception 'not allowed to write in this conversation' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  perform realtime.send(
    jsonb_build_object('user_id', v_who, 'typing', coalesce(typing, true)),
    'typing',
    'inbox:' || conversation::text,
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
  v_conv "better_supabase"."conversations"%rowtype;
  v_staff boolean;
  v_contact_input jsonb := coalesce(input -> 'contact', '{}'::jsonb);
begin
  select * into v_inbox from "better_supabase"."inboxes" where "id" = start_conversation.inbox and "archived_at" is null;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  v_staff := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_inbox."tenant_id", 'inbox.reply'), false);
  if v_staff then
    if jsonb_typeof(input -> 'contact') = 'string' then
      v_contact_input := jsonb_build_object('id', input ->> 'contact');
    end if;
    if v_contact_input = '{}'::jsonb then
      raise exception 'input.contact is required' using errcode = '22023', hint = 'CONTACT_REQUIRED';
    end if;
  elsif (select auth.uid()) is not null and v_inbox."channel" = 'in_app' and coalesce((v_inbox."settings" ->> 'widget')::boolean, false) then
    v_contact_input := jsonb_build_object(
      'user_id', (select auth.uid()),
      'name', v_contact_input ->> 'name',
      'email', coalesce((select auth.jwt()) ->> 'email', v_contact_input ->> 'email')
    );
  else
    raise exception 'not allowed to open a conversation in this inbox' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  v_contact := "better_supabase"."inbox_resolve_contact"(v_inbox."tenant_id", v_contact_input);
  insert into "better_supabase"."conversations" ("tenant_id", "inbox_id", "contact_id", "subject", "priority", "bot_mode", "thread_id", "assignee_id", "metadata")
  values (
    v_inbox."tenant_id", v_inbox."id", v_contact."id", input ->> 'subject', coalesce(input ->> 'priority', 'normal'),
    coalesce(input ->> 'bot_mode', v_inbox."bot_mode"), input ->> 'thread_id',
    case when v_staff then (input ->> 'assignee_id')::uuid end, coalesce(input -> 'metadata', '{}'::jsonb)
  )
  returning * into v_conv;
  if v_conv."thread_id" is null then
    update "better_supabase"."conversations" set "thread_id" = 'inbox:' || "id"::text
    where "id" = v_conv."id"
    returning * into v_conv;
  end if;
  insert into "better_supabase"."conversation_events" ("tenant_id", "conversation_id", "type", "actor_id", "data")
  values (v_conv."tenant_id", v_conv."id", 'opened', (select auth.uid()), '{}'::jsonb);
  
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

CREATE OR REPLACE FUNCTION better_supabase.store_inbound_event (
  adapter     text,
  body        text,
  external_id text  DEFAULT NULL::text,
  headers     jsonb DEFAULT '{}'::jsonb,
  inbox       uuid  DEFAULT NULL::uuid,
  tenant      uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  insert into "better_supabase"."inbound_events" ("adapter", "body", "external_id", "headers", "inbox_id", "tenant_id")
  values (adapter, body, external_id, coalesce(headers, '{}'::jsonb), inbox, tenant)
  on conflict do nothing
  returning "id" into v_id;
  if v_id is not null then
    return jsonb_build_object('id', v_id, 'duplicate', false);
  end if;
  select e."id" into v_id from "better_supabase"."inbound_events" e where e."adapter" = adapter and e."external_id" = external_id;
  return jsonb_build_object('id', v_id, 'duplicate', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_append (
  stream_id text,
  from_idx  integer,
  chunks    text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_stream "better_supabase"."streams"%rowtype;
  v_next integer;
  v_wake boolean;
begin
  select * into v_stream from "better_supabase"."streams" where "id" = stream_append.stream_id;
  if not found then
    raise exception 'stream % does not exist', stream_append.stream_id
      using errcode = 'P0002', hint = 'STREAM_NOT_FOUND';
  end if;
  if v_stream."closed_at" is not null then
    raise exception 'stream % is closed', stream_append.stream_id
      using errcode = 'P0001', hint = 'STREAM_CLOSED';
  end if;
  select coalesce(max("idx") + 1, 0) into v_next from "better_supabase"."stream_chunks" where "stream_id" = stream_append.stream_id;
  if from_idx < 0 or from_idx > v_next then
    raise exception 'stream % is at chunk %, not %', stream_append.stream_id, v_next, from_idx
      using errcode = 'P0001', hint = 'STREAM_GAP';
  end if;
  insert into "better_supabase"."stream_chunks" ("stream_id", "idx", "data")
  select stream_append.stream_id, from_idx + (n.ord - 1)::integer, n.chunk
  from unnest(coalesce(chunks, '{}'::text[])) with ordinality as n(chunk, ord)
  on conflict do nothing;
  v_next := greatest(v_next, from_idx + coalesce(cardinality(chunks), 0));
  v_wake := v_stream."wake" and coalesce(cardinality(chunks), 0) > 0;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'append', 'stream:' || stream_append.stream_id, true);
  end if;
  return jsonb_build_object('next', v_next, 'cancelled', v_stream."cancel_requested_at" is not null);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_cancel (
  stream_id text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_wake boolean;
begin
  update "better_supabase"."streams" set "cancel_requested_at" = now()
  where "id" = stream_cancel.stream_id
    and "cancel_requested_at" is null
    and "closed_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "owner_id" = (select auth.uid()))
  returning "wake" into v_wake;
  if not found then
    return false;
  end if;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'cancel', 'stream:' || stream_cancel.stream_id, true);
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_close (
  stream_id text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_wake boolean;
begin
  update "better_supabase"."streams" set "closed_at" = now()
  where "id" = stream_close.stream_id and "closed_at" is null
  returning "wake" into v_wake;
  if not found then
    return false;
  end if;
  
  if v_wake and to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send('{}'::jsonb, 'close', 'stream:' || stream_close.stream_id, true);
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_open (
  stream_id text,
  owner     uuid     DEFAULT NULL::uuid,
  tenant    uuid     DEFAULT NULL::uuid,
  kind      text     DEFAULT 'default'::text,
  ttl       interval DEFAULT '1 day'::interval,
  wake      boolean  DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_created boolean;
begin
  insert into "better_supabase"."streams" ("id", "owner_id", "tenant_id", "kind", "wake", "expires_at")
  values (stream_id, owner, tenant, coalesce(kind, 'default'), coalesce(wake, true), now() + coalesce(ttl, interval '1 day'))
  on conflict ("id") do nothing
  returning true into v_created;
  return coalesce(v_created, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_read (
  stream_id text,
  from_idx  integer DEFAULT 0,
  max       integer DEFAULT 1000
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_stream "better_supabase"."streams"%rowtype;
  v_chunks text[];
  v_next integer;
  v_last integer;
begin
  select * into v_stream from "better_supabase"."streams" where "id" = stream_read.stream_id;
  if not found then
    return jsonb_build_object('found', false, 'chunks', '[]'::jsonb, 'next', greatest(coalesce(from_idx, 0), 0), 'done', true, 'cancelled', false);
  end if;
  select coalesce(array_agg(r."data" order by r."idx"), '{}'::text[]) into v_chunks
  from (
    select "data", "idx" from "better_supabase"."stream_chunks"
    where "stream_id" = stream_read.stream_id and "idx" >= greatest(coalesce(from_idx, 0), 0)
    order by "idx"
    limit least(greatest(coalesce(max, 1000), 0), 10000)
  ) r;
  v_next := greatest(coalesce(from_idx, 0), 0) + cardinality(v_chunks);
  select coalesce(max("idx") + 1, 0) into v_last from "better_supabase"."stream_chunks" where "stream_id" = stream_read.stream_id;
  return jsonb_build_object(
    'found', true,
    'chunks', to_jsonb(v_chunks),
    'next', v_next,
    'done', v_stream."closed_at" is not null and v_next >= v_last,
    'cancelled', v_stream."cancel_requested_at" is not null
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stream_status (
  stream_id text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'next', (select coalesce(max(ch."idx") + 1, 0) from "better_supabase"."stream_chunks" ch where ch."stream_id" = st."id"),
    'closed', st."closed_at" is not null,
    'cancelled', st."cancel_requested_at" is not null,
    'kind', st."kind",
    'expires_at', st."expires_at"
  )
  from "better_supabase"."streams" st
  where st."id" = stream_status.stream_id;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unschedule_job (
  job_name text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regnamespace('cron') is null then
    return false;
  end if;
  return cron.unschedule(job_name);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unschedule_tenant (
  tenant text
)
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select 0;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_inbox (
  inbox uuid,
  patch jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inboxes"%rowtype;
begin
  select * into v_row from "better_supabase"."inboxes" where "id" = update_inbox.inbox for update;
  if not found then
    raise exception 'inbox not found' using errcode = 'P0002', hint = 'INBOX_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'inbox.manage'), false)) then
    raise exception 'not allowed to manage inboxes' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  update "better_supabase"."inboxes" set
    "name" = coalesce(patch ->> 'name', "name"),
    "settings" = "settings" || coalesce(patch -> 'settings', '{}'::jsonb),
    "bot_mode" = coalesce(patch ->> 'bot_mode', "bot_mode"),
    "channel_address" = case when patch ? 'address' then patch ->> 'address' else "channel_address" end,
    "installation_id" = case when patch ? 'installation_id' then (patch ->> 'installation_id')::uuid else "installation_id" end,
    "archived_at" = case when patch ? 'archived' then (case when (patch ->> 'archived')::boolean then coalesce("archived_at", now()) end) else "archived_at" end
  where "id" = update_inbox.inbox
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.upsert_contact (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', upsert_contact.tenant, 'inbox.reply'), false)) then
    raise exception 'not allowed to edit contacts' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  return to_jsonb("better_supabase"."inbox_resolve_contact"(upsert_contact.tenant, coalesce(input, '{}'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.upsert_message_template (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."message_templates"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', tenant, 'inbox.manage'), false)) then
    raise exception 'not allowed to manage templates' using errcode = '42501', hint = 'INBOX_FORBIDDEN';
  end if;
  insert into "better_supabase"."message_templates" as t ("tenant_id", "inbox_id", "name", "channel", "language", "body", "variables", "external_id")
  values (tenant, (input ->> 'inbox_id')::uuid, input ->> 'name', input ->> 'channel', coalesce(input ->> 'language', 'en'), input ->> 'body', coalesce(input -> 'variables', '[]'::jsonb), input ->> 'external_id')
  on conflict ("tenant_id", "channel", "name", "language") do update set
    "inbox_id" = excluded."inbox_id",
    "body" = excluded."body",
    "variables" = excluded."variables",
    "external_id" = excluded."external_id"
  returning * into v_row;
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.wake_snoozed_conversations()
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  update "better_supabase"."conversations" set "status" = 'open', "snoozed_until" = null
  where "status" = 'snoozed' and "snoozed_until" <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

ALTER TABLE "better_supabase"."chat_installations"
  ADD CONSTRAINT "chat_installations_installed_by_fkey" FOREIGN KEY (installed_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."contact_identities"
  ADD CONSTRAINT "contact_identities_contact_id_fkey" FOREIGN KEY (contact_id) REFERENCES better_supabase.contacts(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."contacts"
  ADD CONSTRAINT "contacts_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."conversation_events"
  ADD CONSTRAINT "conversation_events_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."conversation_participants"
  ADD CONSTRAINT "conversation_participants_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversation_reads"
  ADD CONSTRAINT "conversation_reads_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversations"
  ADD CONSTRAINT "conversations_assignee_id_fkey" FOREIGN KEY (assignee_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."conversations"
  ADD CONSTRAINT "conversations_contact_id_fkey" FOREIGN KEY (contact_id) REFERENCES better_supabase.contacts(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversation_events"
  ADD CONSTRAINT "conversation_events_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES better_supabase.conversations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversation_participants"
  ADD CONSTRAINT "conversation_participants_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES better_supabase.conversations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversation_reads"
  ADD CONSTRAINT "conversation_reads_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES better_supabase.conversations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."inbox_members"
  ADD CONSTRAINT "inbox_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."inbox_mentions"
  ADD CONSTRAINT "inbox_mentions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."inbox_messages"
  ADD CONSTRAINT "inbox_messages_author_id_fkey" FOREIGN KEY (author_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."inbox_messages"
  ADD CONSTRAINT "inbox_messages_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES better_supabase.conversations(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."inbox_mentions"
  ADD CONSTRAINT "inbox_mentions_message_id_fkey" FOREIGN KEY (message_id) REFERENCES better_supabase.inbox_messages(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."inbox_messages"
  ADD CONSTRAINT "inbox_messages_reply_to_fkey" FOREIGN KEY (reply_to) REFERENCES better_supabase.inbox_messages(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."inbox_team_members"
  ADD CONSTRAINT "inbox_team_members_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversations"
  ADD CONSTRAINT "conversations_team_id_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.inbox_teams(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."inbox_team_members"
  ADD CONSTRAINT "inbox_team_members_team_id_fkey" FOREIGN KEY (team_id) REFERENCES better_supabase.inbox_teams(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."conversations"
  ADD CONSTRAINT "conversations_inbox_id_fkey" FOREIGN KEY (inbox_id) REFERENCES better_supabase.inboxes(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."inbound_events"
  ADD CONSTRAINT "inbound_events_inbox_id_fkey" FOREIGN KEY (inbox_id) REFERENCES better_supabase.inboxes(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."inbox_members"
  ADD CONSTRAINT "inbox_members_inbox_id_fkey" FOREIGN KEY (inbox_id) REFERENCES better_supabase.inboxes(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."message_deliveries"
  ADD CONSTRAINT "message_deliveries_message_id_fkey" FOREIGN KEY (message_id) REFERENCES better_supabase.inbox_messages(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."message_templates"
  ADD CONSTRAINT "message_templates_inbox_id_fkey" FOREIGN KEY (inbox_id) REFERENCES better_supabase.inboxes(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."streams"
  ADD CONSTRAINT "streams_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stream_chunks"
  ADD CONSTRAINT "stream_chunks_stream_id_fkey" FOREIGN KEY (stream_id) REFERENCES better_supabase.streams(id) ON DELETE CASCADE;

CREATE INDEX chat_installations_installed_by_idx ON better_supabase.chat_installations USING btree (installed_by);

CREATE INDEX chat_installations_tenant_idx ON better_supabase.chat_installations USING btree (tenant_id);

CREATE INDEX chat_state_cache_expires_idx ON better_supabase.chat_state_cache USING btree (expires_at)
  WHERE (expires_at IS NOT NULL);

CREATE INDEX chat_state_lists_expires_idx ON better_supabase.chat_state_lists USING btree (expires_at)
  WHERE (expires_at IS NOT NULL);

CREATE INDEX chat_state_lists_key_idx ON better_supabase.chat_state_lists USING btree (key_prefix, list_key, id);

CREATE INDEX chat_state_locks_expires_idx ON better_supabase.chat_state_locks USING btree (expires_at);

CREATE INDEX chat_state_queues_expires_idx ON better_supabase.chat_state_queues USING btree (expires_at);

CREATE INDEX chat_state_queues_thread_idx ON better_supabase.chat_state_queues USING btree (key_prefix, thread_id, id);

CREATE INDEX contact_identities_contact_idx ON better_supabase.contact_identities USING btree (contact_id);

CREATE INDEX contacts_email_idx ON better_supabase.contacts USING btree (tenant_id, lower(email));

CREATE INDEX contacts_user_id_idx ON better_supabase.contacts USING btree (user_id);

CREATE UNIQUE INDEX contacts_user_idx ON better_supabase.contacts USING btree (tenant_id, user_id)
  WHERE (user_id IS NOT NULL);

CREATE INDEX conversation_events_actor_idx ON better_supabase.conversation_events USING btree (actor_id);

CREATE INDEX conversation_events_conversation_idx ON better_supabase.conversation_events USING btree (conversation_id, id);

CREATE INDEX conversation_participants_user_idx ON better_supabase.conversation_participants USING btree (user_id);

CREATE INDEX conversation_reads_user_idx ON better_supabase.conversation_reads USING btree (user_id);

CREATE INDEX conversations_assignee_idx ON better_supabase.conversations USING btree (assignee_id)
  WHERE (assignee_id IS NOT NULL);

CREATE INDEX conversations_contact_idx ON better_supabase.conversations USING btree (contact_id);

CREATE INDEX conversations_inbox_idx ON better_supabase.conversations USING btree (inbox_id);

CREATE INDEX conversations_list_idx ON better_supabase.conversations USING btree (tenant_id, status, last_message_at DESC, id);

CREATE INDEX conversations_team_idx ON better_supabase.conversations USING btree (team_id)
  WHERE (team_id IS NOT NULL);

CREATE UNIQUE INDEX conversations_thread_idx ON better_supabase.conversations USING btree (inbox_id, thread_id)
  WHERE (thread_id IS NOT NULL);

CREATE UNIQUE INDEX inbound_events_external_idx ON better_supabase.inbound_events USING btree (adapter, external_id)
  WHERE (external_id IS NOT NULL);

CREATE INDEX inbound_events_inbox_idx ON better_supabase.inbound_events USING btree (inbox_id);

CREATE INDEX inbound_events_status_idx ON better_supabase.inbound_events USING btree (status, received_at);

CREATE INDEX inbox_members_user_idx ON better_supabase.inbox_members USING btree (user_id);

CREATE INDEX inbox_mentions_user_idx ON better_supabase.inbox_mentions USING btree (user_id, created_at DESC);

CREATE INDEX inbox_messages_author_idx ON better_supabase.inbox_messages USING btree (author_id);

CREATE INDEX inbox_messages_conversation_idx ON better_supabase.inbox_messages USING btree (conversation_id, created_at, id);

CREATE UNIQUE INDEX inbox_messages_external_idx ON better_supabase.inbox_messages USING btree (conversation_id, external_id)
  WHERE (external_id IS NOT NULL);

CREATE INDEX inbox_messages_reply_idx ON better_supabase.inbox_messages USING btree (reply_to)
  WHERE (reply_to IS NOT NULL);

CREATE INDEX inbox_team_members_user_idx ON better_supabase.inbox_team_members USING btree (user_id);

CREATE UNIQUE INDEX inboxes_address_idx ON better_supabase.inboxes USING btree (channel, channel_address)
  WHERE ((channel_address IS NOT NULL) AND (archived_at IS NULL));

CREATE INDEX inboxes_tenant_idx ON better_supabase.inboxes USING btree (tenant_id);

CREATE INDEX message_deliveries_external_idx ON better_supabase.message_deliveries USING btree (channel, external_id)
  WHERE (external_id IS NOT NULL);

CREATE INDEX message_templates_inbox_idx ON better_supabase.message_templates USING btree (inbox_id);

CREATE INDEX streams_expires_idx ON better_supabase.streams USING btree (expires_at);

CREATE INDEX streams_owner_idx ON better_supabase.streams USING btree (owner_id);

CREATE INDEX streams_tenant_idx ON better_supabase.streams USING btree (tenant_id);

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.contacts
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.conversations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER conversations_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.conversations
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.inbox_conversation_broadcast();

CREATE TRIGGER inbox_messages_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.inbox_messages
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.inbox_message_broadcast();

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.inboxes
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.message_deliveries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE TRIGGER message_deliveries_broadcast
  AFTER INSERT OR UPDATE OF status ON better_supabase.message_deliveries
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.inbox_delivery_broadcast();

CREATE TRIGGER bs_updated_at
  BEFORE UPDATE ON better_supabase.message_templates
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.set_updated_at('updated_at');

CREATE POLICY "contact_identities_staff_read" ON "better_supabase"."contact_identities"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "contacts_read" ON "better_supabase"."contacts"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)) OR (user_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "conversation_events_staff_read" ON "better_supabase"."conversation_events"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "conversation_participants_staff_read" ON "better_supabase"."conversation_participants"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.conversations c
  WHERE ((c.id = conversation_participants.conversation_id) AND (c.tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with))))));

CREATE POLICY "conversation_reads_own" ON "better_supabase"."conversation_reads"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "conversations_read" ON "better_supabase"."conversations"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)) OR (contact_id IN ( SELECT better_supabase.inbox_contact_ids() AS
    inbox_contact_ids))));

CREATE POLICY "inbox_members_staff_read" ON "better_supabase"."inbox_members"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.inboxes i
  WHERE ((i.id = inbox_members.inbox_id) AND (i.tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with))))));

CREATE POLICY "inbox_mentions_staff_read" ON "better_supabase"."inbox_mentions"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "inbox_messages_read" ON "better_supabase"."inbox_messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)) OR ((kind = 'message'::text) AND (conversation_id IN ( SELECT
    better_supabase.inbox_contact_conversation_ids() AS inbox_contact_conversation_ids)))));

CREATE POLICY "inbox_team_members_staff_read" ON "better_supabase"."inbox_team_members"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.inbox_teams t
  WHERE ((t.id = inbox_team_members.team_id) AND (t.tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with))))));

CREATE POLICY "inbox_teams_staff_read" ON "better_supabase"."inbox_teams"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "inboxes_staff_read" ON "better_supabase"."inboxes"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "message_deliveries_staff_read" ON "better_supabase"."message_deliveries"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "message_templates_staff_read" ON "better_supabase"."message_templates"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('inbox.read'::text) AS tenant_ids_with)));

CREATE POLICY "stream_chunks_owner_read" ON "better_supabase"."stream_chunks"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.streams st
  WHERE ((st.id = stream_chunks.stream_id) AND (st.owner_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "streams_owner_read" ON "better_supabase"."streams"
  FOR SELECT
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "bs_inbox_broadcast" ON "realtime"."messages"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((extension = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND (( SELECT realtime.topic() AS topic) ~~ ('inbox:'::text || '%'::text)) AND (( SELECT realtime.topic() AS
    topic) !~~ ('inbox:org:'::text || '%'::text)) AND better_supabase.inbox_conversation_allowed(substr(( SELECT realtime.topic() AS topic), 7))));

CREATE POLICY "bs_inbox_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND (( SELECT realtime.topic() AS topic) ~~ 'inbox:%'::text) AND (((( SELECT realtime.topic() AS topic) ~~
    'inbox:org:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 11) IN ( SELECT (x.x)::text AS x
   FROM better_supabase.tenant_ids_with('inbox.read'::text) x(x)))) OR
     ((( SELECT realtime.topic() AS topic) ~~ 'inbox:%'::text) AND (( SELECT realtime.topic() AS topic) !~~ 'inbox:org:%'::text) AND
     better_supabase.inbox_conversation_allowed(substr(( SELECT realtime.topic() AS topic), 7))))));

CREATE POLICY "bs_streams_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'stream:%'::text) AND (EXISTS ( SELECT 1
   FROM better_supabase.streams st
  WHERE ((st.id = substr(( SELECT realtime.topic() AS topic), 8)) AND (st.owner_id = ( SELECT auth.uid() AS uid)))))));

CREATE POLICY "bs_inbox_files_read" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING (((bucket_id = 'inbox-files'::text) AND better_supabase.inbox_file_allowed(name, false)));

CREATE POLICY "bs_inbox_files_write" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH CHECK (((bucket_id = 'inbox-files'::text) AND better_supabase.inbox_file_allowed(name, true)));

REVOKE ALL ON FUNCTION "api"."assign_conversation"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."assign_conversation"(uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_inbox"(uuid, text, text, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_inbox"(uuid, text, text, jsonb, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."create_inbox_team"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_inbox_team"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_message_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_message_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."edit_message"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."edit_message"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_conversation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_conversation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_message"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_message"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."inbox_counts"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."inbox_counts"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_conversation_events"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_conversation_events"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_conversations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_conversations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_messages"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_messages"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_conversation_read"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_conversation_read"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."pending_inbound_events"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pending_inbound_events"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_contact"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_contact"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_inbound_events"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_inbound_events"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."react_to_message"(uuid, text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."react_to_message"(uuid, text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_delivery"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_delivery"(uuid, text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_inbound"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_inbound"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."send_message"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."send_message"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_bot_mode"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_bot_mode"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_conversation_status"(uuid, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_conversation_status"(uuid, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_delivery_status"(text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_delivery_status"(text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_inbound_event_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_inbound_event_status"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_inbox_member"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_inbox_member"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_inbox_team_member"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_inbox_team_member"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_typing"(uuid, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_typing"(uuid, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."start_conversation"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."start_conversation"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."update_inbox"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_inbox"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."upsert_contact"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."upsert_contact"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."upsert_message_template"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."upsert_message_template"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."wake_snoozed_conversations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."wake_snoozed_conversations"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."advance_schedule"(text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."advance_schedule"(text, timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."assign_conversation"(uuid, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."assign_conversation"(uuid, uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_install"(text, text, uuid, jsonb, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_install"(text, text, uuid, jsonb, uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_installation"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_installation"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_acquire_lock"(text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_acquire_lock"(text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_append_to_list"(text, text, jsonb, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_append_to_list"(text, text, jsonb, integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_delete"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_delete"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_dequeue"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_dequeue"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_enqueue"(text, text, jsonb, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_enqueue"(text, text, jsonb, timestamp WITH time zone, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_extend_lock"(text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_extend_lock"(text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_force_release_lock"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_force_release_lock"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_get"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_get"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_get_list"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_get_list"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_is_subscribed"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_is_subscribed"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_queue_depth"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_queue_depth"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_release_lock"(text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_release_lock"(text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_set"(text, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_set"(text, text, jsonb, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_set_if_not_exists"(text, text, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_set_if_not_exists"(text, text, jsonb, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_subscribe"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_subscribe"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_state_unsubscribe"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_state_unsubscribe"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."chat_uninstall"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."chat_uninstall"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_due_schedules"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_due_schedules"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_jobs"(text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_jobs"(text, integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_job"(text, bigint, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_job"(text, bigint, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_inbox"(uuid, text, text, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_inbox"(uuid, text, text, jsonb, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_inbox_team"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_inbox_team"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_message_template"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_message_template"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."edit_message"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."edit_message"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."enqueue_job"(text, jsonb, integer, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."enqueue_job"(text, jsonb, integer, integer, text, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ensure_job_queue"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ensure_job_queue"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."extend_job_lease"(text, bigint, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."extend_job_lease"(text, bigint, integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fail_job"(text, bigint, integer, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fail_job"(text, bigint, integer, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_conversation"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_conversation"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_message"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_message"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_add_message"(uuid, jsonb, text, uuid, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."inbox_contact_conversation_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_contact_conversation_ids"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_contact_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_contact_ids"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_conversation_allowed"(text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_conversation_allowed"(text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_conversation_broadcast"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."inbox_conversation_json"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_conversation_json"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_counts"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_counts"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_delivery_broadcast"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."inbox_file_allowed"(text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."inbox_file_allowed"(text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inbox_message_broadcast"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."inbox_resolve_contact"(uuid, jsonb) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."index_job_queue"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."index_job_queue"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."job_queue_stats"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."job_queue_stats"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_chat_installations"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_chat_installations"(uuid, text, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_conversation_events"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_conversation_events"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_conversations"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_conversations"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_dead_jobs"(text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_dead_jobs"(text, integer, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_messages"(uuid, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_messages"(uuid, timestamp WITH time zone, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_schedules"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_schedules"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_conversation_read"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_conversation_read"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pending_inbound_events"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pending_inbound_events"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_chat_state"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_chat_state"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_contact"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_contact"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_inbound_events"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_inbound_events"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_job_archive"(text, interval, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_job_archive"(text, interval, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_streams"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_streams"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."react_to_message"(uuid, text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."react_to_message"(uuid, text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_delivery"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_delivery"(uuid, text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_inbound"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_inbound"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."replay_dead_job"(text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."replay_dead_job"(text, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."retry_dead_jobs"(text, bigint[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."retry_dead_jobs"(text, bigint[], integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."schedule_job"(text, text, text, jsonb, text, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."schedule_job"(text, text, text, jsonb, text, timestamp WITH time zone, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."send_message"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."send_message"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_bot_mode"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_bot_mode"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_conversation_status"(uuid, text, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_conversation_status"(uuid, text, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_delivery_status"(text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_delivery_status"(text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_inbound_event_status"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_inbound_event_status"(uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_inbox_member"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_inbox_member"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_inbox_team_member"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_inbox_team_member"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_typing"(uuid, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_typing"(uuid, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."start_conversation"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."start_conversation"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."store_inbound_event"(text, text, text, jsonb, uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stream_append"(text, integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stream_append"(text, integer, text[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stream_cancel"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stream_cancel"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stream_close"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stream_close"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stream_open"(text, uuid, uuid, text, interval, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stream_open"(text, uuid, uuid, text, interval, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stream_read"(text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stream_read"(text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."stream_status"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."stream_status"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unschedule_job"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unschedule_job"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unschedule_tenant"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unschedule_tenant"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_inbox"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_inbox"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."upsert_contact"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."upsert_contact"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."upsert_message_template"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."upsert_message_template"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."wake_snoozed_conversations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."wake_snoozed_conversations"() TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."chat_installations" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."chat_state_cache" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."chat_state_lists" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."chat_state_locks" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."chat_state_queues" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."chat_state_subscriptions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."contact_identities" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."contact_identities" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."contacts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."contacts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."conversation_events" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."conversation_events" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."conversation_participants" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."conversation_participants" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."conversation_reads" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."conversation_reads" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."conversations" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."conversations" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inbound_events" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."inbox_members" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inbox_members" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."inbox_mentions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inbox_mentions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."inbox_messages" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inbox_messages" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."inbox_team_members" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inbox_team_members" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."inbox_teams" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inbox_teams" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."inboxes" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."inboxes" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."message_deliveries" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."message_deliveries" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."message_templates" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."message_templates" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."stream_chunks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."stream_chunks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."streams" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."streams" TO "service_role";
