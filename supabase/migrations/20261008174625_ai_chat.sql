SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."ai_chat_shares" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "chat_id"    uuid                     NOT NULL,
  "token_hash" text                     NOT NULL,
  "leaf_id"    text                     NOT NULL,
  "created_by" uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "revoked_at" timestamp with time zone,
  CONSTRAINT "ai_chat_shares_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_chat_shares_token_hash_check" CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text)),
  CONSTRAINT "ai_chat_shares_token_hash_key" UNIQUE (token_hash)
);

ALTER TABLE "better_supabase"."ai_chat_shares"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_chats" (
  "id"               uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id"  uuid                     NOT NULL,
  "owner_id"         uuid                     NOT NULL,
  "project_id"       uuid,
  "agent_id"         text,
  "title"            text                     NOT NULL DEFAULT ''::text,
  "model"            text,
  "visibility"       text                     NOT NULL DEFAULT 'private'::text,
  "pinned"           boolean                  NOT NULL DEFAULT false,
  "archived_at"      timestamp with time zone,
  "is_temporary"     boolean                  NOT NULL DEFAULT false,
  "expires_at"       timestamp with time zone,
  "current_leaf_id"  text,
  "active_stream_id" text,
  "active_run_id"    uuid,
  "last_message_at"  timestamp with time zone NOT NULL DEFAULT clock_timestamp(),
  "created_at"       timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"       timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_chats_agent_id_check" CHECK ((length(agent_id) <= 200)),
  CONSTRAINT "ai_chats_check" CHECK (((NOT is_temporary) OR (expires_at IS NOT NULL))),
  CONSTRAINT "ai_chats_model_check" CHECK ((length(model) <= 200)),
  CONSTRAINT "ai_chats_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_chats_title_check" CHECK ((length(title) <= 300)),
  CONSTRAINT "ai_chats_visibility_check" CHECK ((visibility = ANY (ARRAY['private'::text, 'organization'::text])))
);

ALTER TABLE "better_supabase"."ai_chats"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_message_feedback" (
  "chat_id"    uuid                     NOT NULL,
  "message_id" text                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "rating"     smallint                 NOT NULL,
  "reason"     text,
  "comment"    text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_message_feedback_comment_check" CHECK ((length(comment) <= 4000)),
  CONSTRAINT "ai_message_feedback_pkey" PRIMARY KEY (chat_id, message_id, user_id),
  CONSTRAINT "ai_message_feedback_rating_check" CHECK ((rating = ANY (ARRAY['-1'::integer, 1]))),
  CONSTRAINT "ai_message_feedback_reason_check" CHECK ((length(reason) <= 200))
);

ALTER TABLE "better_supabase"."ai_message_feedback"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_message_sources" (
  "chat_id"           uuid  NOT NULL,
  "message_id"        text  NOT NULL,
  "source_id"         text  NOT NULL,
  "source_type"       text  NOT NULL DEFAULT 'url'::text,
  "url"               text,
  "title"             text,
  "provider_metadata" jsonb,
  CONSTRAINT "ai_message_sources_pkey" PRIMARY KEY (chat_id, message_id, source_id),
  CONSTRAINT "ai_message_sources_source_type_check" CHECK ((source_type = ANY (ARRAY['url'::text, 'document'::text])))
);

ALTER TABLE "better_supabase"."ai_message_sources"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_messages" (
  "chat_id"    uuid                     NOT NULL,
  "id"         text                     NOT NULL,
  "parent_id"  text,
  "owner_id"   uuid                     NOT NULL,
  "role"       text                     NOT NULL,
  "parts"      jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "format"     text                     NOT NULL DEFAULT 'canonical'::text,
  "native"     jsonb,
  "metadata"   jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "model"      text,
  "status"     text                     NOT NULL DEFAULT 'complete'::text,
  "seq"        bigint                   GENERATED ALWAYS AS IDENTITY NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_messages_format_check" CHECK (((length(format) >= 1) AND (length(format) <= 50))),
  CONSTRAINT "ai_messages_id_check" CHECK (((length(id) >= 1) AND (length(id) <= 200))),
  CONSTRAINT "ai_messages_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text)),
  CONSTRAINT "ai_messages_parts_check"
    CHECK
    (((jsonb_typeof(parts) = 'array'::text) AND (NOT jsonb_path_exists(parts,
    '$[*]?(!((((((((@."type" == "text" || @."type" == "reasoning") || @."type" == "file") || @."type" == "tool-call") || @."type" == "tool-result") || @."type" == "tool-approval") || @."type" == "source") || @."type" == "data") || @."type" == "step"))'::jsonpath)))),
  CONSTRAINT "ai_messages_pkey" PRIMARY KEY (chat_id, id),
  CONSTRAINT "ai_messages_role_check" CHECK ((role = ANY (ARRAY['system'::text, 'user'::text, 'assistant'::text, 'tool'::text]))),
  CONSTRAINT "ai_messages_status_check" CHECK ((status = ANY (ARRAY['complete'::text, 'aborted'::text, 'error'::text])))
);

ALTER TABLE "better_supabase"."ai_messages"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_model_catalog" (
  "model_id"     text                     NOT NULL,
  "provider"     text                     NOT NULL DEFAULT ''::text,
  "name"         text                     NOT NULL DEFAULT ''::text,
  "pricing"      jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "capabilities" jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "plans"        text[]                   NOT NULL DEFAULT '{}'::text[],
  "enabled"      boolean                  NOT NULL DEFAULT true,
  "refreshed_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_model_catalog_model_id_check" CHECK (((length(model_id) >= 1) AND (length(model_id) <= 200))),
  CONSTRAINT "ai_model_catalog_pkey" PRIMARY KEY (model_id)
);

ALTER TABLE "better_supabase"."ai_model_catalog"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_moderation_events" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "chat_id"         uuid,
  "message_id"      text,
  "user_id"         uuid,
  "stage"           text                     NOT NULL,
  "category"        text                     NOT NULL,
  "score"           real,
  "action"          text                     NOT NULL,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_moderation_events_action_check" CHECK ((action = ANY (ARRAY['allow'::text, 'flag'::text, 'redact'::text, 'block'::text]))),
  CONSTRAINT "ai_moderation_events_category_check" CHECK (((length(category) >= 1) AND (length(category) <= 100))),
  CONSTRAINT "ai_moderation_events_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_moderation_events_stage_check" CHECK ((stage = ANY (ARRAY['input'::text, 'output'::text, 'tool'::text])))
);

ALTER TABLE "better_supabase"."ai_moderation_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_pending_inputs" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "chat_id"      uuid                     NOT NULL,
  "owner_id"     uuid                     NOT NULL,
  "run_id"       uuid,
  "tool_call_id" text,
  "question"     text                     NOT NULL,
  "schema"       jsonb,
  "answer"       jsonb,
  "answered_at"  timestamp with time zone,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_pending_inputs_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_pending_inputs_question_check" CHECK (((length(question) >= 1) AND (length(question) <= 2000)))
);

ALTER TABLE "better_supabase"."ai_pending_inputs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_projects" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "owner_id"        uuid                     NOT NULL,
  "name"            text                     NOT NULL,
  "instructions"    text                     NOT NULL DEFAULT ''::text,
  "default_model"   text,
  "pinned"          boolean                  NOT NULL DEFAULT false,
  "archived_at"     timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_projects_default_model_check" CHECK ((length(default_model) <= 200)),
  CONSTRAINT "ai_projects_instructions_check" CHECK ((length(instructions) <= 20000)),
  CONSTRAINT "ai_projects_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "ai_projects_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."ai_projects"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_runs" (
  "id"                     uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "chat_id"                uuid                     NOT NULL,
  "owner_id"               uuid                     NOT NULL,
  "assistant_message_id"   text,
  "stream_id"              text,
  "engine"                 text                     NOT NULL DEFAULT 'ai-sdk'::text,
  "model"                  text,
  "status"                 text                     NOT NULL DEFAULT 'running'::text,
  "provider_generation_id" text,
  "usage"                  jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "cost_micro_usd"         bigint,
  "error"                  text,
  "started_at"             timestamp with time zone NOT NULL DEFAULT now(),
  "ended_at"               timestamp with time zone,
  CONSTRAINT "ai_runs_cost_micro_usd_check" CHECK ((cost_micro_usd >= 0)),
  CONSTRAINT "ai_runs_engine_check" CHECK (((length(engine) >= 1) AND (length(engine) <= 50))),
  CONSTRAINT "ai_runs_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_runs_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'cancel_requested'::text, 'done'::text, 'error'::text, 'stopped'::text]))),
  CONSTRAINT "ai_runs_usage_check" CHECK ((jsonb_typeof(usage) = 'object'::text))
);

ALTER TABLE "better_supabase"."ai_runs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_tool_approvals" (
  "approval_id"  text                     NOT NULL,
  "chat_id"      uuid                     NOT NULL,
  "owner_id"     uuid                     NOT NULL,
  "run_id"       uuid,
  "message_id"   text,
  "tool"         text                     NOT NULL,
  "tool_call_id" text                     NOT NULL,
  "input"        jsonb,
  "decision"     text,
  "reason"       text,
  "signature"    text,
  "decided_by"   uuid,
  "decided_at"   timestamp with time zone,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_tool_approvals_approval_id_check" CHECK (((length(approval_id) >= 1) AND (length(approval_id) <= 200))),
  CONSTRAINT "ai_tool_approvals_decision_check" CHECK ((decision = ANY (ARRAY['approved'::text, 'denied'::text]))),
  CONSTRAINT "ai_tool_approvals_pkey" PRIMARY KEY (approval_id),
  CONSTRAINT "ai_tool_approvals_reason_check" CHECK ((length(reason) <= 2000)),
  CONSTRAINT "ai_tool_approvals_tool_check" CHECK (((length(tool) >= 1) AND (length(tool) <= 200)))
);

ALTER TABLE "better_supabase"."ai_tool_approvals"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_tool_policies" (
  "organization_id" uuid                     NOT NULL,
  "tool"            text                     NOT NULL,
  "policy"          text                     NOT NULL,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_tool_policies_pkey" PRIMARY KEY (organization_id, tool),
  CONSTRAINT "ai_tool_policies_policy_check" CHECK ((policy = ANY (ARRAY['auto'::text, 'ask'::text, 'deny'::text]))),
  CONSTRAINT "ai_tool_policies_tool_check" CHECK (((length(tool) >= 1) AND (length(tool) <= 200)))
);

ALTER TABLE "better_supabase"."ai_tool_policies"
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

ALTER TABLE "better_supabase"."ai_chats"
  ADD COLUMN "search_tsv" tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, title)) STORED;

ALTER TABLE "better_supabase"."ai_messages"
  ADD COLUMN "search_tsv" tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, jsonb_path_query_array(parts, '$[*]?(@."type" == "text")."text"'::jsonpath))) STORED;

CREATE OR REPLACE FUNCTION api.ai_chat_can_read (
  chat uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_chat_can_read"($1) $function$;

CREATE OR REPLACE FUNCTION api.ai_message_path (
  chat           uuid,
  leaf           text    DEFAULT NULL::text,
  include_native boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_message_path"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.ai_message_siblings (
  chat       uuid,
  message_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_message_siblings"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.ai_tool_policies_for (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."ai_tool_policies_for"($1) $function$;

CREATE OR REPLACE FUNCTION api.allowed_ai_models (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."allowed_ai_models"($1) $function$;

CREATE OR REPLACE FUNCTION api.answer_ai_pending_input (
  id     uuid,
  answer jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."answer_ai_pending_input"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.append_ai_user_message (
  chat       uuid,
  message    jsonb,
  trigger    text  DEFAULT 'submit-message'::text,
  message_id text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."append_ai_user_message"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.claim_ai_chat_stream (
  chat       uuid,
  stream     text,
  model      text DEFAULT NULL::text,
  message_id text DEFAULT NULL::text,
  engine     text DEFAULT 'ai-sdk'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_ai_chat_stream"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.create_ai_chat (
  tenant uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_ai_chat"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.decide_ai_tool_approval (
  approval_id text,
  approved    boolean,
  reason      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decide_ai_tool_approval"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.delete_ai_chat (
  chat uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ai_chat"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_ai_project (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ai_project"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_chat (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_chat"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_ai_tool_approvals (
  chat uuid,
  ids  text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_ai_tool_approvals"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_shared_ai_chat"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_chat_shares (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_chat_shares"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_chats (
  tenant   uuid    DEFAULT NULL::uuid,
  search   text    DEFAULT NULL::text,
  project  uuid    DEFAULT NULL::uuid,
  pinned   boolean DEFAULT NULL::boolean,
  archived boolean DEFAULT false,
  after    text    DEFAULT NULL::text,
  size     integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_chats"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_moderation_events (
  tenant uuid,
  size   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_moderation_events"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_projects (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_projects"($1) $function$;

CREATE OR REPLACE FUNCTION api.open_ai_pending_input (
  chat  uuid,
  input jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."open_ai_pending_input"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_ai_chats (
  batch integer DEFAULT 1000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_ai_chats"($1) $function$;

CREATE OR REPLACE FUNCTION api.purge_streams (
  older_than interval DEFAULT '1 day'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_streams"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.rate_ai_message (
  chat       uuid,
  message_id text,
  rating     integer,
  reason     text    DEFAULT NULL::text,
  comment    text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rate_ai_message"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.record_ai_moderation_event (
  event jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_ai_moderation_event"($1) $function$;

CREATE OR REPLACE FUNCTION api.record_ai_tool_approval (
  chat     uuid,
  approval jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_ai_tool_approval"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.release_ai_chat_stream (
  chat           uuid,
  stream         text,
  status         text   DEFAULT 'done'::text,
  usage          jsonb  DEFAULT NULL::jsonb,
  generation_id  text   DEFAULT NULL::text,
  error          text   DEFAULT NULL::text,
  cost_micro_usd bigint DEFAULT NULL::bigint
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_ai_chat_stream"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.request_ai_chat_stop (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_ai_chat_stop"($1) $function$;

CREATE OR REPLACE FUNCTION api.revoke_ai_chat_share (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."revoke_ai_chat_share"($1) $function$;

CREATE OR REPLACE FUNCTION api.save_ai_assistant_message (
  chat      uuid,
  message   jsonb,
  parent_id text,
  status    text  DEFAULT 'complete'::text,
  model     text  DEFAULT NULL::text,
  format    text  DEFAULT 'canonical'::text,
  native    jsonb DEFAULT NULL::jsonb,
  run       uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_ai_assistant_message"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.save_ai_project (
  id     uuid,
  tenant uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_ai_project"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_ai_run_cost (
  generation_id  text,
  cost_micro_usd bigint,
  usage          jsonb  DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_ai_run_cost"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.set_ai_tool_policy (
  tenant uuid,
  tool   text,
  policy text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_ai_tool_policy"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.share_ai_chat (
  chat uuid,
  leaf text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."share_ai_chat"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.stream_append (
  stream_id text,
  from_idx  integer,
  chunks    text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_append"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.stream_cancel (
  stream_id text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_cancel"($1) $function$;

CREATE OR REPLACE FUNCTION api.stream_close (
  stream_id text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_close"($1) $function$;

CREATE OR REPLACE FUNCTION api.stream_open (
  stream_id text,
  owner     uuid     DEFAULT NULL::uuid,
  tenant    uuid     DEFAULT NULL::uuid,
  kind      text     DEFAULT 'default'::text,
  ttl       interval DEFAULT '1 day'::interval,
  wake      boolean  DEFAULT true
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_open"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.stream_read (
  stream_id text,
  from_idx  integer DEFAULT 0,
  max       integer DEFAULT 1000
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_read"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.stream_status (
  stream_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."stream_status"($1) $function$;

CREATE OR REPLACE FUNCTION api.switch_ai_branch (
  chat       uuid,
  message_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."switch_ai_branch"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.update_ai_chat (
  chat   uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_ai_chat"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.upsert_ai_models (
  models jsonb,
  prune  boolean DEFAULT false
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."upsert_ai_models"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_chat_can_read (
  chat uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select exists (
    select 1 from "better_supabase"."ai_chats" x
    where x."id" = ai_chat_can_read.chat
      and (
        coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
        or x."owner_id" = (select auth.uid())
        or (x."visibility" = 'organization' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai_chat.read'), false))
      )
  );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_chat_notify (
  chat    uuid,
  owner   uuid,
  event   text,
  payload jsonb,
  list    boolean
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_payload jsonb := coalesce(payload, '{}'::jsonb) || jsonb_build_object('chatId', chat);
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is null then
    return;
  end if;
  perform realtime.send(v_payload, event, 'ai-chat:' || chat::text, true);
  if list and owner is not null then
    perform realtime.send(v_payload, event, 'ai-chats:' || owner::text, true);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_message_path (
  chat           uuid,
  leaf           text    DEFAULT NULL::text,
  include_native boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_leaf text;
begin
  if not "better_supabase"."ai_chat_can_read"(ai_message_path.chat) then
    raise exception 'No chat %', ai_message_path.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  select coalesce(ai_message_path.leaf, x."current_leaf_id") into v_leaf from "better_supabase"."ai_chats" x where x."id" = ai_message_path.chat;
  if v_leaf is null then
    return '[]'::jsonb;
  end if;
  return "better_supabase"."ai_message_path_of"(ai_message_path.chat, v_leaf, coalesce(ai_message_path.include_native, false));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_message_path_of (
  chat           uuid,
  leaf           text,
  include_native boolean
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with recursive up as (
    select x.*, 0 as depth from "better_supabase"."ai_messages" x
    where x."chat_id" = ai_message_path_of.chat and x."id" = ai_message_path_of.leaf
    union all
    select x.*, up.depth + 1 from "better_supabase"."ai_messages" x
    join up on x."chat_id" = up."chat_id" and x."id" = up."parent_id"
    where up.depth < 10000
  )
  select coalesce(jsonb_agg(
    jsonb_build_object('id', up."id", 'parent_id', up."parent_id", 'role', up."role", 'parts', up."parts", 'metadata', up."metadata", 'format', up."format", 'native', case when ai_message_path_of.include_native then up."native" end, 'model', up."model", 'status', up."status", 'created_at', up."created_at") || jsonb_build_object(
      'sibling_count', (select count(*) from "better_supabase"."ai_messages" sb where sb."chat_id" = up."chat_id" and sb."parent_id" is not distinct from up."parent_id"),
      'sibling_index', (select count(*) from "better_supabase"."ai_messages" sb where sb."chat_id" = up."chat_id" and sb."parent_id" is not distinct from up."parent_id" and sb."seq" < up."seq")
    )
    order by up.depth desc
  ), '[]'::jsonb)
  from up;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_message_siblings (
  chat       uuid,
  message_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_parent text;
begin
  if not "better_supabase"."ai_chat_can_read"(ai_message_siblings.chat) then
    raise exception 'No chat %', ai_message_siblings.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  select x."parent_id" into v_parent from "better_supabase"."ai_messages" x
  where x."chat_id" = ai_message_siblings.chat and x."id" = ai_message_siblings.message_id;
  if not found then
    raise exception 'No message %', ai_message_siblings.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'role', x."role", 'created_at', x."created_at") order by x."seq"), '[]'::jsonb)
    from "better_supabase"."ai_messages" x
    where x."chat_id" = ai_message_siblings.chat and x."parent_id" is not distinct from v_parent
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ai_tool_policies_for (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', ai_tool_policies_for.tenant, 'ai_chat.read'), false)) then
    return '{}'::jsonb;
  end if;
  return (
    select coalesce(jsonb_object_agg(x."tool", x."policy"), '{}'::jsonb)
    from "better_supabase"."ai_tool_policies" x where x."organization_id" = ai_tool_policies_for.tenant
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.allowed_ai_models (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid := allowed_ai_models.tenant;
begin
  if v_tenant is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'ai_chat.read'), false)) then
    v_tenant := null;
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('model_id', x."model_id", 'provider', x."provider", 'name', x."name", 'pricing', x."pricing", 'capabilities', x."capabilities", 'plans', to_jsonb(x."plans"), 'enabled', x."enabled", 'refreshed_at', x."refreshed_at") order by x."provider", x."name"), '[]'::jsonb)
    from "better_supabase"."ai_model_catalog" x
    where x."enabled" and (cardinality(x."plans") = 0 or (v_tenant is not null and x."plans" && better_supabase.tenant_entitlements(v_tenant)))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.answer_ai_pending_input (
  id     uuid,
  answer jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_pending_inputs";
begin
  select * into v_row from "better_supabase"."ai_pending_inputs" x where x."id" = answer_ai_pending_input.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No question %', answer_ai_pending_input.id using errcode = 'P0002', hint = 'AI_INPUT_NOT_FOUND';
  end if;
  if v_row."answered_at" is not null then
    raise exception 'Question % was answered', answer_ai_pending_input.id using errcode = 'P0001', hint = 'AI_INPUT_ANSWERED';
  end if;
  update "better_supabase"."ai_pending_inputs" x set "answer" = coalesce(answer_ai_pending_input.answer, 'null'::jsonb), "answered_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'input.answered', jsonb_build_object('inputId', v_row."id"), false);
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'tool_call_id', v_row."tool_call_id", 'question', v_row."question", 'schema', v_row."schema", 'answer', v_row."answer", 'answered_at', v_row."answered_at", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.append_ai_user_message (
  chat       uuid,
  message    jsonb,
  trigger    text  DEFAULT 'submit-message'::text,
  message_id text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_existing "better_supabase"."ai_messages";
  v_id text;
  v_parent text;
  v_target text;
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = append_ai_user_message.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', append_ai_user_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if coalesce(append_ai_user_message.trigger, 'submit-message') = 'regenerate-message' then
    v_target := coalesce(append_ai_user_message.message_id, v_chat."current_leaf_id");
    select * into v_existing from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_target;
    if not found then
      raise exception 'No message % to regenerate', v_target using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
    end if;
    v_parent := case when v_existing."role" = 'user' then v_existing."id" else v_existing."parent_id" end;
    update "better_supabase"."ai_chats" x set "current_leaf_id" = v_parent, "updated_at" = now() where x."id" = v_chat."id";
    perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'leaf.changed', jsonb_build_object('leafId', v_parent), false);
    return jsonb_build_object('message_id', v_parent, 'parent_id', v_parent, 'created', false);
  elsif append_ai_user_message.trigger <> 'submit-message' then
    raise exception 'Unknown trigger %', append_ai_user_message.trigger using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  if jsonb_typeof(append_ai_user_message.message) is distinct from 'object'
    or append_ai_user_message.message ->> 'role' is distinct from 'user'
    or nullif(append_ai_user_message.message ->> 'id', '') is null
    or jsonb_typeof(append_ai_user_message.message -> 'parts') is distinct from 'array' then
    raise exception 'A user message needs an id, role user and parts' using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  v_id := append_ai_user_message.message ->> 'id';
  select * into v_existing from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_id;
  if found then
    if v_existing."parts" = append_ai_user_message.message -> 'parts' then
      return jsonb_build_object('message_id', v_id, 'parent_id', v_existing."parent_id", 'created', false);
    end if;
    v_parent := v_existing."parent_id";
    v_id := gen_random_uuid()::text;
  elsif append_ai_user_message.message_id is not null then
    select x."parent_id" into v_parent from "better_supabase"."ai_messages" x
    where x."chat_id" = v_chat."id" and x."id" = append_ai_user_message.message_id;
    if not found then
      raise exception 'No message %', append_ai_user_message.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
    end if;
  else
    v_parent := v_chat."current_leaf_id";
  end if;
  insert into "better_supabase"."ai_messages" ("chat_id", "id", "parent_id", "owner_id", "role", "parts", "metadata")
  values (
    v_chat."id", v_id, v_parent, v_chat."owner_id", 'user', append_ai_user_message.message -> 'parts',
    case when jsonb_typeof(append_ai_user_message.message -> 'metadata') = 'object' then append_ai_user_message.message -> 'metadata' else '{}'::jsonb end
  );
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_id, "last_message_at" = clock_timestamp(), "updated_at" = now() where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", v_chat."owner_id", 'message.saved', jsonb_build_object('messageId', v_id), not v_chat."is_temporary");
  return jsonb_build_object('message_id', v_id, 'parent_id', v_parent, 'created', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_ai_chat_stream (
  chat       uuid,
  stream     text,
  model      text DEFAULT NULL::text,
  message_id text DEFAULT NULL::text,
  engine     text DEFAULT 'ai-sdk'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_run "better_supabase"."ai_runs";
  v_run_id uuid;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = claim_ai_chat_stream.chat for update;
  if not found then
    raise exception 'No chat %', claim_ai_chat_stream.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_chat."active_stream_id" is not null then
    select * into v_run from "better_supabase"."ai_runs" x where x."id" = v_chat."active_run_id";
    if v_chat."active_stream_id" = claim_ai_chat_stream.stream then
      return jsonb_build_object('claimed', true, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    if v_run."id" is not null
      and v_run."status" in ('queued', 'running', 'cancel_requested')
      and v_run."started_at" > now() - interval '10 minutes'
      and not exists (
        select 1 from "better_supabase"."streams" so
        where so."id" = v_chat."active_stream_id" and so."closed_at" is not null
      ) then
      return jsonb_build_object('claimed', false, 'stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
    end if;
    update "better_supabase"."ai_runs" x set "status" = 'stopped', "ended_at" = now()
    where x."id" = v_chat."active_run_id" and x."ended_at" is null;
  end if;
  insert into "better_supabase"."ai_runs" ("chat_id", "owner_id", "assistant_message_id", "stream_id", "engine", "model")
  values (v_chat."id", v_chat."owner_id", claim_ai_chat_stream.message_id, claim_ai_chat_stream.stream, coalesce(claim_ai_chat_stream.engine, 'ai-sdk'), coalesce(claim_ai_chat_stream.model, v_chat."model"))
  returning "id" into v_run_id;
  update "better_supabase"."ai_chats" x set "active_stream_id" = claim_ai_chat_stream.stream, "active_run_id" = v_run_id, "updated_at" = now()
  where x."id" = v_chat."id";
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'stream.started', jsonb_build_object('streamId', claim_ai_chat_stream.stream, 'runId', v_run_id), false);
  return jsonb_build_object('claimed', true, 'stream_id', claim_ai_chat_stream.stream, 'run_id', v_run_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_ai_chat (
  tenant uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(create_ai_chat.fields, '{}'::jsonb);
  v_owner uuid := auth.uid();
  v_row "better_supabase"."ai_chats";
  v_id uuid;
  v_project uuid := (v_fields ->> 'project_id')::uuid;
  v_temporary boolean := coalesce((v_fields ->> 'is_temporary')::boolean, false);
  v_visibility text := coalesce(v_fields ->> 'visibility', 'private');
begin
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    v_owner := coalesce((v_fields ->> 'owner_id')::uuid, v_owner);
  elsif not coalesce(better_supabase.can('tenant', create_ai_chat.tenant, 'ai_chat.create'), false) then
    raise exception 'You may not start chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_owner is null then
    raise exception 'Sign in first' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_visibility = 'organization' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_ai_chat.tenant, 'ai_chat.share'), false)) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  v_id := coalesce((v_fields ->> 'id')::uuid, gen_random_uuid());
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = v_id;
  if found then
    if v_row."owner_id" <> v_owner then
      raise exception 'Chat % exists', v_id using errcode = '23505', hint = 'AI_CHAT_EXISTS';
    end if;
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_owner and pr."organization_id" = create_ai_chat.tenant) then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chats" ("id", "organization_id", "owner_id", "project_id", "agent_id", "title", "model", "visibility", "is_temporary", "expires_at")
  values (
    v_id, create_ai_chat.tenant, v_owner, v_project, v_fields ->> 'agent_id',
    coalesce(v_fields ->> 'title', ''), v_fields ->> 'model', v_visibility, v_temporary,
    case when v_temporary then now() + interval '1 day' end
  )
  returning * into v_row;
  if not v_temporary then
    perform "better_supabase"."ai_chat_notify"(v_id, v_owner, 'chat.created', '{}'::jsonb, true);
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_ai_tool_approval (
  approval_id text,
  approved    boolean,
  reason      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."ai_tool_approvals";
  v_decision text := case when decide_ai_tool_approval.approved then 'approved' else 'denied' end;
begin
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = decide_ai_tool_approval.approval_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No approval %', decide_ai_tool_approval.approval_id using errcode = 'P0002', hint = 'AI_APPROVAL_NOT_FOUND';
  end if;
  if decide_ai_tool_approval.approved is null then
    raise exception 'Approve or deny' using errcode = '22023', hint = 'AI_APPROVAL_INVALID';
  end if;
  if v_row."decision" is not null then
    if v_row."decision" = v_decision then
      return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
    end if;
    raise exception 'Approval % was already %', v_row."approval_id", v_row."decision" using errcode = 'P0001', hint = 'AI_APPROVAL_DECIDED';
  end if;
  update "better_supabase"."ai_tool_approvals" x set
    "decision" = v_decision,
    "reason" = decide_ai_tool_approval.reason,
    "decided_by" = auth.uid(),
    "decided_at" = now()
  where x."approval_id" = v_row."approval_id"
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."chat_id", null, 'approval.decided', jsonb_build_object('approvalId', v_row."approval_id", 'decision', v_decision), false);
  return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_chat (
  chat uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_chats";
begin
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = delete_ai_chat.chat for update;
  if not found then
    return false;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid()) or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'No chat %', delete_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  delete from "better_supabase"."ai_chats" x where x."id" = delete_ai_chat.chat;
  perform "better_supabase"."ai_chat_notify"(v_row."id", v_row."owner_id", 'chat.deleted', '{}'::jsonb, true);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_project (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."ai_projects" x where x."id" = delete_ai_project.id and x."owner_id" = (select auth.uid());
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_chat (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_chats";
begin
  if not "better_supabase"."ai_chat_can_read"(get_ai_chat.chat) then
    raise exception 'No chat %', get_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = get_ai_chat.chat;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_ai_tool_approvals (
  chat uuid,
  ids  text[] DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not "better_supabase"."ai_chat_can_read"(get_ai_tool_approvals.chat) then
    raise exception 'No chat %', get_ai_tool_approvals.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('approval_id', x."approval_id", 'chat_id', x."chat_id", 'run_id', x."run_id", 'message_id', x."message_id", 'tool', x."tool", 'tool_call_id', x."tool_call_id", 'input', x."input", 'decision', x."decision", 'reason', x."reason", 'signature', x."signature", 'decided_by', x."decided_by", 'decided_at', x."decided_at", 'created_at', x."created_at") order by x."created_at"), '[]'::jsonb)
    from "better_supabase"."ai_tool_approvals" x
    where x."chat_id" = get_ai_tool_approvals.chat
      and (get_ai_tool_approvals.ids is null or x."approval_id" = any (get_ai_tool_approvals.ids))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_shared_ai_chat (
  token text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_share "better_supabase"."ai_chat_shares";
  v_chat "better_supabase"."ai_chats";
begin
  if get_shared_ai_chat.token is null or get_shared_ai_chat.token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select * into v_share from "better_supabase"."ai_chat_shares" x
  where x."token_hash" = encode(sha256(convert_to(get_shared_ai_chat.token, 'UTF8')), 'hex') and x."revoked_at" is null;
  if not found then
    return null;
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = v_share."chat_id";
  return jsonb_build_object(
    'chat', jsonb_build_object('id', v_chat."id", 'title', v_chat."title", 'model', v_chat."model", 'created_at', v_chat."created_at"),
    'leaf_id', v_share."leaf_id",
    'messages', "better_supabase"."ai_message_path_of"(v_chat."id", v_share."leaf_id", false)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_chat_shares (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id", 'leaf_id', x."leaf_id", 'created_by', x."created_by",
    'created_at', x."created_at", 'revoked_at', x."revoked_at"
  ) order by x."created_at" desc), '[]'::jsonb)
  from "better_supabase"."ai_chat_shares" x
  join "better_supabase"."ai_chats" c on c."id" = x."chat_id"
  where x."chat_id" = list_ai_chat_shares.chat
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or c."owner_id" = (select auth.uid()));
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_chats (
  tenant   uuid    DEFAULT NULL::uuid,
  search   text    DEFAULT NULL::text,
  project  uuid    DEFAULT NULL::uuid,
  pinned   boolean DEFAULT NULL::boolean,
  archived boolean DEFAULT false,
  after    text    DEFAULT NULL::text,
  size     integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_uid uuid := auth.uid();
  v_query tsquery;
  v_at timestamptz;
  v_id uuid;
  v_size integer := least(greatest(coalesce(list_ai_chats.size, 50), 1), 200);
  v_items jsonb;
  v_next text;
begin
  if v_uid is null then
    return jsonb_build_object('items', '[]'::jsonb, 'next', null);
  end if;
  if nullif(btrim(list_ai_chats.search), '') is not null then
    v_query := websearch_to_tsquery('simple'::regconfig, list_ai_chats.search);
  end if;
  if list_ai_chats.after is not null then
    v_at := split_part(list_ai_chats.after, '|', 1)::timestamptz;
    v_id := split_part(list_ai_chats.after, '|', 2)::uuid;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', page."id", 'organization_id', page."organization_id", 'owner_id', page."owner_id", 'project_id', page."project_id", 'agent_id', page."agent_id", 'title', page."title", 'model', page."model", 'visibility', page."visibility", 'pinned', page."pinned", 'archived_at', page."archived_at", 'is_temporary', page."is_temporary", 'expires_at', page."expires_at", 'current_leaf_id', page."current_leaf_id", 'active_stream_id', page."active_stream_id", 'active_run_id', page."active_run_id", 'last_message_at', page."last_message_at", 'created_at', page."created_at", 'updated_at', page."updated_at") order by page."last_message_at" desc, page."id" desc), '[]'::jsonb)
  into v_items
  from (
    select x.* from "better_supabase"."ai_chats" x
    where x."owner_id" = v_uid
      and not x."is_temporary"
      and (list_ai_chats.tenant is null or x."organization_id" = list_ai_chats.tenant)
      and (list_ai_chats.project is null or x."project_id" = list_ai_chats.project)
      and (list_ai_chats.pinned is null or x."pinned" = list_ai_chats.pinned)
      and (list_ai_chats.archived is null or (x."archived_at" is not null) = list_ai_chats.archived)
      and (v_at is null or (x."last_message_at", x."id") < (v_at, v_id))
      and (
        v_query is null
        or x."search_tsv" @@ v_query
        or exists (select 1 from "better_supabase"."ai_messages" mm where mm."chat_id" = x."id" and mm."search_tsv" @@ v_query)
      )
    order by x."last_message_at" desc, x."id" desc
    limit v_size + 1
  ) page;
  if jsonb_array_length(v_items) > v_size then
    v_items := v_items - v_size;
    v_next := (v_items -> (v_size - 1) ->> 'last_message_at') || '|' || (v_items -> (v_size - 1) ->> 'id');
  end if;
  return jsonb_build_object('items', v_items, 'next', v_next);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_moderation_events (
  tenant uuid,
  size   integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_ai_moderation_events.tenant, 'ai_chat.moderate'), false)) then
    raise exception 'You may not review moderation here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', page."id", 'organization_id', page."organization_id", 'chat_id', page."chat_id", 'message_id', page."message_id", 'user_id', page."user_id", 'stage', page."stage", 'category', page."category", 'score', page."score", 'action', page."action", 'created_at', page."created_at") order by page."created_at" desc), '[]'::jsonb)
    from (
      select * from "better_supabase"."ai_moderation_events" x
      where x."organization_id" = list_ai_moderation_events.tenant
      order by x."created_at" desc
      limit least(greatest(coalesce(list_ai_moderation_events.size, 100), 1), 1000)
    ) page
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_projects (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'name', x."name", 'instructions', x."instructions", 'default_model', x."default_model", 'pinned', x."pinned", 'archived_at', x."archived_at", 'created_at', x."created_at", 'updated_at', x."updated_at") order by x."pinned" desc, x."updated_at" desc), '[]'::jsonb)
  from "better_supabase"."ai_projects" x
  where x."owner_id" = (select auth.uid()) and x."organization_id" = list_ai_projects.tenant;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_ai_pending_input (
  chat  uuid,
  input jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_pending_inputs";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = open_ai_pending_input.chat;
  if not found then
    raise exception 'No chat %', open_ai_pending_input.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_pending_inputs" ("chat_id", "owner_id", "run_id", "tool_call_id", "question", "schema")
  values (
    v_chat."id", v_chat."owner_id", (open_ai_pending_input.input ->> 'run_id')::uuid,
    open_ai_pending_input.input ->> 'tool_call_id', open_ai_pending_input.input ->> 'question',
    open_ai_pending_input.input -> 'schema'
  )
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'input.requested', jsonb_build_object('inputId', v_row."id"), false);
  return jsonb_build_object('id', v_row."id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'tool_call_id', v_row."tool_call_id", 'question', v_row."question", 'schema', v_row."schema", 'answer', v_row."answer", 'answered_at', v_row."answered_at", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_ai_chats (
  batch integer DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  with doomed as (
    select x."id" from "better_supabase"."ai_chats" x
    where x."is_temporary" and x."expires_at" <= now()
    limit greatest(coalesce(purge_ai_chats.batch, 1000), 1)
  )
  delete from "better_supabase"."ai_chats" c using doomed where c."id" = doomed."id";
  get diagnostics v_count = row_count;
  return v_count;
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

CREATE OR REPLACE FUNCTION better_supabase.rate_ai_message (
  chat       uuid,
  message_id text,
  rating     integer,
  reason     text    DEFAULT NULL::text,
  comment    text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null or not "better_supabase"."ai_chat_can_read"(rate_ai_message.chat) then
    raise exception 'No chat %', rate_ai_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = rate_ai_message.chat and x."id" = rate_ai_message.message_id) then
    raise exception 'No message %', rate_ai_message.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  if rate_ai_message.rating is null then
    delete from "better_supabase"."ai_message_feedback" x
    where x."chat_id" = rate_ai_message.chat and x."message_id" = rate_ai_message.message_id and x."user_id" = auth.uid();
    return null;
  end if;
  insert into "better_supabase"."ai_message_feedback" ("chat_id", "message_id", "user_id", "rating", "reason", "comment")
  values (rate_ai_message.chat, rate_ai_message.message_id, auth.uid(), rate_ai_message.rating, rate_ai_message.reason, rate_ai_message.comment)
  on conflict ("chat_id", "message_id", "user_id") do update set
    "rating" = excluded."rating", "reason" = excluded."reason", "comment" = excluded."comment", "updated_at" = now();
  return jsonb_build_object('chat_id', rate_ai_message.chat, 'message_id', rate_ai_message.message_id, 'rating', rate_ai_message.rating, 'reason', rate_ai_message.reason, 'comment', rate_ai_message.comment);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ai_moderation_event (
  event jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."ai_moderation_events";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_moderation_events" ("organization_id", "chat_id", "message_id", "user_id", "stage", "category", "score", "action")
  values (
    (record_ai_moderation_event.event ->> 'organization_id')::uuid,
    (record_ai_moderation_event.event ->> 'chat_id')::uuid,
    record_ai_moderation_event.event ->> 'message_id',
    (record_ai_moderation_event.event ->> 'user_id')::uuid,
    record_ai_moderation_event.event ->> 'stage',
    record_ai_moderation_event.event ->> 'category',
    (record_ai_moderation_event.event ->> 'score')::real,
    record_ai_moderation_event.event ->> 'action'
  )
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'chat_id', v_row."chat_id", 'message_id', v_row."message_id", 'user_id', v_row."user_id", 'stage', v_row."stage", 'category', v_row."category", 'score', v_row."score", 'action', v_row."action", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_ai_tool_approval (
  chat     uuid,
  approval jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_row "better_supabase"."ai_tool_approvals";
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = record_ai_tool_approval.chat;
  if not found then
    raise exception 'No chat %', record_ai_tool_approval.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_tool_approvals" ("approval_id", "chat_id", "owner_id", "run_id", "message_id", "tool", "tool_call_id", "input", "signature")
  values (
    record_ai_tool_approval.approval ->> 'approval_id', v_chat."id", v_chat."owner_id",
    (record_ai_tool_approval.approval ->> 'run_id')::uuid, record_ai_tool_approval.approval ->> 'message_id',
    record_ai_tool_approval.approval ->> 'tool', record_ai_tool_approval.approval ->> 'tool_call_id',
    record_ai_tool_approval.approval -> 'input', record_ai_tool_approval.approval ->> 'signature'
  )
  on conflict ("approval_id") do nothing;
  select * into v_row from "better_supabase"."ai_tool_approvals" x where x."approval_id" = record_ai_tool_approval.approval ->> 'approval_id';
  if v_row."chat_id" <> v_chat."id" then
    raise exception 'Approval % belongs to another chat', v_row."approval_id" using errcode = '23505', hint = 'AI_APPROVAL_EXISTS';
  end if;
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'approval.requested', jsonb_build_object('approvalId', v_row."approval_id"), false);
  return jsonb_build_object('approval_id', v_row."approval_id", 'chat_id', v_row."chat_id", 'run_id', v_row."run_id", 'message_id', v_row."message_id", 'tool', v_row."tool", 'tool_call_id', v_row."tool_call_id", 'input', v_row."input", 'decision', v_row."decision", 'reason', v_row."reason", 'signature', v_row."signature", 'decided_by', v_row."decided_by", 'decided_at', v_row."decided_at", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_ai_chat_stream (
  chat           uuid,
  stream         text,
  status         text   DEFAULT 'done'::text,
  usage          jsonb  DEFAULT NULL::jsonb,
  generation_id  text   DEFAULT NULL::text,
  error          text   DEFAULT NULL::text,
  cost_micro_usd bigint DEFAULT NULL::bigint
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_status text := coalesce(release_ai_chat_stream.status, 'done');
  v_found boolean := false;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if v_status not in ('done', 'error', 'stopped') then
    raise exception 'A run ends done, error or stopped, not %', v_status using errcode = '22023', hint = 'AI_RUN_INVALID';
  end if;
  update "better_supabase"."ai_runs" x set
    "status" = v_status,
    "usage" = coalesce(release_ai_chat_stream.usage, x."usage"),
    "provider_generation_id" = coalesce(release_ai_chat_stream.generation_id, x."provider_generation_id"),
    "error" = release_ai_chat_stream.error,
    "cost_micro_usd" = coalesce(release_ai_chat_stream.cost_micro_usd, x."cost_micro_usd"),
    "ended_at" = coalesce(x."ended_at", now())
  where x."chat_id" = release_ai_chat_stream.chat and x."stream_id" = release_ai_chat_stream.stream;
  update "better_supabase"."ai_chats" x set "active_stream_id" = null, "active_run_id" = null, "updated_at" = now()
  where x."id" = release_ai_chat_stream.chat and x."active_stream_id" = release_ai_chat_stream.stream
  returning true into v_found;
  if coalesce(v_found, false) then
    perform "better_supabase"."ai_chat_notify"(release_ai_chat_stream.chat, null, 'stream.ended', jsonb_build_object('streamId', release_ai_chat_stream.stream, 'status', v_status), false);
  end if;
  return coalesce(v_found, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_ai_chat_stop (
  chat uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat "better_supabase"."ai_chats";
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = request_ai_chat_stop.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', request_ai_chat_stop.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_chat."active_stream_id" is null then
    return null;
  end if;
  update "better_supabase"."ai_runs" x set "status" = 'cancel_requested'
  where x."id" = v_chat."active_run_id" and x."status" in ('queued', 'running');
  perform "better_supabase"."stream_cancel"(v_chat."active_stream_id");
  perform "better_supabase"."ai_chat_notify"(v_chat."id", null, 'stream.stopping', jsonb_build_object('streamId', v_chat."active_stream_id"), false);
  return jsonb_build_object('stream_id', v_chat."active_stream_id", 'run_id', v_chat."active_run_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_ai_chat_share (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  update "better_supabase"."ai_chat_shares" x set "revoked_at" = now()
  where x."id" = revoke_ai_chat_share.id
    and x."revoked_at" is null
    and (
      coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
      or x."created_by" = (select auth.uid())
      or exists (select 1 from "better_supabase"."ai_chats" c where c."id" = x."chat_id" and c."owner_id" = (select auth.uid()))
    );
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_assistant_message (
  chat      uuid,
  message   jsonb,
  parent_id text,
  status    text  DEFAULT 'complete'::text,
  model     text  DEFAULT NULL::text,
  format    text  DEFAULT 'canonical'::text,
  native    jsonb DEFAULT NULL::jsonb,
  run       uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_chat "better_supabase"."ai_chats";
  v_id text := save_ai_assistant_message.message ->> 'id';
  v_role text := coalesce(save_ai_assistant_message.message ->> 'role', 'assistant');
  v_status text := coalesce(save_ai_assistant_message.status, 'complete');
  v_created boolean;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = save_ai_assistant_message.chat for update;
  if not found then
    raise exception 'No chat %', save_ai_assistant_message.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if nullif(v_id, '') is null or v_role = 'user'
    or jsonb_typeof(save_ai_assistant_message.message -> 'parts') is distinct from 'array' then
    raise exception 'A reply needs an id, a role other than user and parts' using errcode = '22023', hint = 'AI_MESSAGE_INVALID';
  end if;
  if save_ai_assistant_message.parent_id is not null and not exists (
    select 1 from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = save_ai_assistant_message.parent_id
  ) then
    raise exception 'No message %', save_ai_assistant_message.parent_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_messages" ("chat_id", "id", "parent_id", "owner_id", "role", "parts", "metadata", "format", "native", "model", "status")
  values (
    v_chat."id", v_id, save_ai_assistant_message.parent_id, v_chat."owner_id", v_role,
    save_ai_assistant_message.message -> 'parts',
    case when jsonb_typeof(save_ai_assistant_message.message -> 'metadata') = 'object' then save_ai_assistant_message.message -> 'metadata' else '{}'::jsonb end,
    coalesce(save_ai_assistant_message.format, 'canonical'), save_ai_assistant_message.native,
    save_ai_assistant_message.model, v_status
  )
  on conflict ("chat_id", "id") do update set
    "parts" = excluded."parts",
    "metadata" = excluded."metadata",
    "format" = excluded."format",
    "native" = excluded."native",
    "model" = coalesce(excluded."model", "better_supabase"."ai_messages"."model"),
    "status" = excluded."status"
  returning (xmax = 0) into v_created;
  delete from "better_supabase"."ai_message_sources" x where x."chat_id" = v_chat."id" and x."message_id" = v_id;
  insert into "better_supabase"."ai_message_sources" ("chat_id", "message_id", "source_id", "source_type", "url", "title", "provider_metadata")
  select distinct on (e ->> 'id') v_chat."id", v_id, e ->> 'id', coalesce(e ->> 'sourceType', 'url'), e ->> 'url', e ->> 'title', e -> 'providerMetadata'
  from jsonb_array_elements(save_ai_assistant_message.message -> 'parts') e
  where e ->> 'type' = 'source' and nullif(e ->> 'id', '') is not null and coalesce(e ->> 'sourceType', 'url') in ('url', 'document')
  order by e ->> 'id';
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_id, "last_message_at" = clock_timestamp(), "updated_at" = now() where x."id" = v_chat."id";
  if save_ai_assistant_message.run is not null then
    update "better_supabase"."ai_runs" x set "assistant_message_id" = v_id where x."id" = save_ai_assistant_message.run and x."chat_id" = v_chat."id";
  end if;
  if v_status = 'complete' then
    
  end if;
  perform "better_supabase"."ai_chat_notify"(v_chat."id", v_chat."owner_id", 'message.saved', jsonb_build_object('messageId', v_id), not v_chat."is_temporary");
  return jsonb_build_object('message_id', v_id, 'parent_id', save_ai_assistant_message.parent_id, 'created', v_created);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_project (
  id     uuid,
  tenant uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(save_ai_project.fields, '{}'::jsonb);
  v_row "better_supabase"."ai_projects";
begin
  if save_ai_project.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_ai_project.tenant, 'ai_chat.create'), false) then
      raise exception 'You may not create projects here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_projects" ("organization_id", "owner_id", "name", "instructions", "default_model", "pinned")
    values (
      save_ai_project.tenant, auth.uid(), v_fields ->> 'name', coalesce(v_fields ->> 'instructions', ''),
      v_fields ->> 'default_model', coalesce((v_fields ->> 'pinned')::boolean, false)
    )
    returning * into v_row;
    return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'name', v_row."name", 'instructions', v_row."instructions", 'default_model', v_row."default_model", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
  end if;
  update "better_supabase"."ai_projects" x set
    "name" = coalesce(v_fields ->> 'name', x."name"),
    "instructions" = case when v_fields ? 'instructions' then coalesce(v_fields ->> 'instructions', '') else x."instructions" end,
    "default_model" = case when v_fields ? 'default_model' then v_fields ->> 'default_model' else x."default_model" end,
    "pinned" = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x."pinned" end,
    "archived_at" = case
      when not v_fields ? 'archived' then x."archived_at"
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x."archived_at", now())
    end,
    "updated_at" = now()
  where x."id" = save_ai_project.id and x."owner_id" = (select auth.uid())
  returning * into v_row;
  if not found then
    raise exception 'No project %', save_ai_project.id using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'name', v_row."name", 'instructions', v_row."instructions", 'default_model', v_row."default_model", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ai_run_cost (
  generation_id  text,
  cost_micro_usd bigint,
  usage          jsonb  DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server saves replies' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_runs" x set
    "cost_micro_usd" = set_ai_run_cost.cost_micro_usd,
    "usage" = x."usage" || coalesce(set_ai_run_cost.usage, '{}'::jsonb)
  where x."provider_generation_id" = set_ai_run_cost.generation_id;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_ai_tool_policy (
  tenant uuid,
  tool   text,
  policy text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', set_ai_tool_policy.tenant, 'ai_chat.admin'), false)) then
    raise exception 'You may not change tool policies here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  if set_ai_tool_policy.policy is null then
    delete from "better_supabase"."ai_tool_policies" x where x."organization_id" = set_ai_tool_policy.tenant and x."tool" = set_ai_tool_policy.tool;
    return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', null);
  end if;
  insert into "better_supabase"."ai_tool_policies" ("organization_id", "tool", "policy")
  values (set_ai_tool_policy.tenant, set_ai_tool_policy.tool, set_ai_tool_policy.policy)
  on conflict ("organization_id", "tool") do update set "policy" = excluded."policy", "updated_at" = now();
  return jsonb_build_object('tool', set_ai_tool_policy.tool, 'policy', set_ai_tool_policy.policy);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.share_ai_chat (
  chat uuid,
  leaf text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat "better_supabase"."ai_chats";
  v_leaf text;
  v_token text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  v_id uuid;
  v_created timestamptz;
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = share_ai_chat.chat;
  if not found or v_chat."owner_id" is distinct from auth.uid() then
    raise exception 'No chat %', share_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.can('tenant', v_chat."organization_id", 'ai_chat.share'), false) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  v_leaf := coalesce(share_ai_chat.leaf, v_chat."current_leaf_id");
  if v_leaf is null or not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = v_chat."id" and x."id" = v_leaf) then
    raise exception 'Nothing to share yet' using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  insert into "better_supabase"."ai_chat_shares" ("chat_id", "token_hash", "leaf_id", "created_by")
  values (v_chat."id", encode(sha256(convert_to(v_token, 'UTF8')), 'hex'), v_leaf, auth.uid())
  returning "id", "created_at" into v_id, v_created;
  
  return jsonb_build_object('id', v_id, 'token', v_token, 'leaf_id', v_leaf, 'created_at', v_created);
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

CREATE OR REPLACE FUNCTION better_supabase.switch_ai_branch (
  chat       uuid,
  message_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_chat "better_supabase"."ai_chats";
  v_leaf text;
begin
  select * into v_chat from "better_supabase"."ai_chats" x where x."id" = switch_ai_branch.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_chat."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', switch_ai_branch.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if not exists (select 1 from "better_supabase"."ai_messages" x where x."chat_id" = switch_ai_branch.chat and x."id" = switch_ai_branch.message_id) then
    raise exception 'No message %', switch_ai_branch.message_id using errcode = 'P0002', hint = 'AI_MESSAGE_NOT_FOUND';
  end if;
  with recursive down as (
    select switch_ai_branch.message_id as id, 0 as depth
    union all
    select (
      select c."id" from "better_supabase"."ai_messages" c
      where c."chat_id" = switch_ai_branch.chat and c."parent_id" = down.id
      order by c."seq" desc limit 1
    ), down.depth + 1
    from down
    where down.id is not null and down.depth < 10000
  )
  select d.id into v_leaf from down d where d.id is not null order by d.depth desc limit 1;
  update "better_supabase"."ai_chats" x set "current_leaf_id" = v_leaf, "updated_at" = now() where x."id" = switch_ai_branch.chat;
  perform "better_supabase"."ai_chat_notify"(switch_ai_branch.chat, null, 'leaf.changed', jsonb_build_object('leafId', v_leaf), false);
  return jsonb_build_object('leaf_id', v_leaf);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_ai_chat (
  chat   uuid,
  fields jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_fields jsonb := coalesce(update_ai_chat.fields, '{}'::jsonb);
  v_row "better_supabase"."ai_chats";
  v_project uuid := (v_fields ->> 'project_id')::uuid;
begin
  select * into v_row from "better_supabase"."ai_chats" x where x."id" = update_ai_chat.chat for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = (select auth.uid())) then
    raise exception 'No chat %', update_ai_chat.chat using errcode = 'P0002', hint = 'AI_CHAT_NOT_FOUND';
  end if;
  if v_project is not null and not exists (select 1 from "better_supabase"."ai_projects" pr where pr."id" = v_project and pr."owner_id" = v_row."owner_id" and pr."organization_id" = v_row."organization_id") then
    raise exception 'No project %', v_project using errcode = 'P0002', hint = 'AI_PROJECT_NOT_FOUND';
  end if;
  if v_fields ->> 'visibility' = 'organization' and v_row."visibility" <> 'organization'
    and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.share'), false)) then
    raise exception 'You may not share chats here' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_chats" x set
    "title" = case when v_fields ? 'title' then coalesce(v_fields ->> 'title', '') else x."title" end,
    "model" = case when v_fields ? 'model' then v_fields ->> 'model' else x."model" end,
    "project_id" = case when v_fields ? 'project_id' then v_project else x."project_id" end,
    "agent_id" = case when v_fields ? 'agent_id' then v_fields ->> 'agent_id' else x."agent_id" end,
    "visibility" = case when v_fields ? 'visibility' then coalesce(v_fields ->> 'visibility', 'private') else x."visibility" end,
    "pinned" = case when v_fields ? 'pinned' then coalesce((v_fields ->> 'pinned')::boolean, false) else x."pinned" end,
    "archived_at" = case
      when not v_fields ? 'archived' then x."archived_at"
      when coalesce((v_fields ->> 'archived')::boolean, false) then coalesce(x."archived_at", now())
    end,
    "is_temporary" = x."is_temporary" and coalesce((v_fields ->> 'is_temporary')::boolean, true),
    "expires_at" = case when x."is_temporary" and coalesce((v_fields ->> 'is_temporary')::boolean, true) then x."expires_at" end,
    "updated_at" = now()
  where x."id" = update_ai_chat.chat
  returning * into v_row;
  perform "better_supabase"."ai_chat_notify"(v_row."id", v_row."owner_id", 'chat.updated', '{}'::jsonb, not v_row."is_temporary");
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'project_id', v_row."project_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'model', v_row."model", 'visibility', v_row."visibility", 'pinned', v_row."pinned", 'archived_at', v_row."archived_at", 'is_temporary', v_row."is_temporary", 'expires_at', v_row."expires_at", 'current_leaf_id', v_row."current_leaf_id", 'active_stream_id', v_row."active_stream_id", 'active_run_id', v_row."active_run_id", 'last_message_at', v_row."last_message_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.upsert_ai_models (
  models jsonb,
  prune  boolean DEFAULT false
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
  v_models jsonb := case jsonb_typeof(upsert_ai_models.models)
    when 'array' then upsert_ai_models.models
    when 'object' then coalesce(upsert_ai_models.models -> 'models', '[]'::jsonb)
    else '[]'::jsonb
  end;
begin
  if not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Only the server records this' using errcode = '42501', hint = 'AI_CHAT_FORBIDDEN';
  end if;
  insert into "better_supabase"."ai_model_catalog" ("model_id", "provider", "name", "pricing", "capabilities", "plans", "enabled")
  select
    e ->> 'id',
    coalesce(e ->> 'provider', split_part(e ->> 'id', '/', 1)),
    coalesce(e ->> 'name', e ->> 'id'),
    coalesce(e -> 'pricing', '{}'::jsonb),
    coalesce(e -> 'capabilities', '{}'::jsonb),
    coalesce(array(select jsonb_array_elements_text(e -> 'plans')), '{}'::text[]),
    coalesce((e ->> 'enabled')::boolean, true)
  from jsonb_array_elements(v_models) e
  where nullif(e ->> 'id', '') is not null
  on conflict ("model_id") do update set
    "provider" = excluded."provider",
    "name" = excluded."name",
    "pricing" = excluded."pricing",
    "capabilities" = excluded."capabilities",
    "refreshed_at" = now();
  get diagnostics v_count = row_count;
  if upsert_ai_models.prune then
    delete from "better_supabase"."ai_model_catalog" x
    where x."model_id" not in (select e ->> 'id' from jsonb_array_elements(v_models) e where e ->> 'id' is not null);
  end if;
  return v_count;
end;
$function$;

ALTER TABLE "better_supabase"."ai_chat_shares"
  ADD CONSTRAINT "ai_chat_shares_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_chats"
  ADD CONSTRAINT "ai_chats_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_chat_shares"
  ADD CONSTRAINT "ai_chat_shares_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_message_feedback"
  ADD CONSTRAINT "ai_message_feedback_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_messages"
  ADD CONSTRAINT "ai_messages_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_message_feedback"
  ADD CONSTRAINT "ai_message_feedback_chat_id_message_id_fkey" FOREIGN KEY (chat_id, message_id) REFERENCES better_supabase.ai_messages(chat_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_message_sources"
  ADD CONSTRAINT "ai_message_sources_chat_id_message_id_fkey" FOREIGN KEY (chat_id, message_id) REFERENCES better_supabase.ai_messages(chat_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_messages"
  ADD CONSTRAINT "ai_messages_chat_id_parent_id_fkey" FOREIGN KEY (chat_id, parent_id) REFERENCES better_supabase.ai_messages(chat_id, id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_moderation_events"
  ADD CONSTRAINT "ai_moderation_events_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_moderation_events"
  ADD CONSTRAINT "ai_moderation_events_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_pending_inputs"
  ADD CONSTRAINT "ai_pending_inputs_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_projects"
  ADD CONSTRAINT "ai_projects_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_chats"
  ADD CONSTRAINT "ai_chats_project_id_fkey" FOREIGN KEY (project_id) REFERENCES better_supabase.ai_projects(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_runs"
  ADD CONSTRAINT "ai_runs_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_pending_inputs"
  ADD CONSTRAINT "ai_pending_inputs_run_id_fkey" FOREIGN KEY (run_id) REFERENCES better_supabase.ai_runs(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_tool_approvals"
  ADD CONSTRAINT "ai_tool_approvals_chat_id_fkey" FOREIGN KEY (chat_id) REFERENCES better_supabase.ai_chats(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_tool_approvals"
  ADD CONSTRAINT "ai_tool_approvals_run_id_fkey" FOREIGN KEY (run_id) REFERENCES better_supabase.ai_runs(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."streams"
  ADD CONSTRAINT "streams_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."stream_chunks"
  ADD CONSTRAINT "stream_chunks_stream_id_fkey" FOREIGN KEY (stream_id) REFERENCES better_supabase.streams(id) ON DELETE CASCADE;

CREATE INDEX ai_chat_shares_chat_idx ON better_supabase.ai_chat_shares USING btree (chat_id);

CREATE INDEX ai_chat_shares_created_by_idx ON better_supabase.ai_chat_shares USING btree (created_by);

CREATE INDEX ai_chats_expires_idx ON better_supabase.ai_chats USING btree (expires_at)
  WHERE is_temporary;

CREATE INDEX ai_chats_owner_idx ON better_supabase.ai_chats USING btree (owner_id, last_message_at DESC, id DESC);

CREATE INDEX ai_chats_project_idx ON better_supabase.ai_chats USING btree (project_id);

CREATE INDEX ai_chats_search_idx ON better_supabase.ai_chats USING gin (search_tsv);

CREATE INDEX ai_chats_tenant_idx ON better_supabase.ai_chats USING btree (organization_id);

CREATE INDEX ai_message_feedback_user_idx ON better_supabase.ai_message_feedback USING btree (user_id);

CREATE INDEX ai_messages_owner_idx ON better_supabase.ai_messages USING btree (owner_id);

CREATE INDEX ai_messages_parent_idx ON better_supabase.ai_messages USING btree (chat_id, parent_id);

CREATE INDEX ai_messages_search_idx ON better_supabase.ai_messages USING gin (search_tsv);

CREATE INDEX ai_moderation_events_chat_idx ON better_supabase.ai_moderation_events USING btree (chat_id);

CREATE INDEX ai_moderation_events_tenant_idx ON better_supabase.ai_moderation_events USING btree (organization_id, created_at DESC);

CREATE INDEX ai_moderation_events_user_idx ON better_supabase.ai_moderation_events USING btree (user_id);

CREATE INDEX ai_pending_inputs_chat_idx ON better_supabase.ai_pending_inputs USING btree (chat_id);

CREATE INDEX ai_pending_inputs_owner_idx ON better_supabase.ai_pending_inputs USING btree (owner_id);

CREATE INDEX ai_pending_inputs_run_idx ON better_supabase.ai_pending_inputs USING btree (run_id);

CREATE INDEX ai_projects_owner_idx ON better_supabase.ai_projects USING btree (owner_id, organization_id);

CREATE INDEX ai_runs_chat_idx ON better_supabase.ai_runs USING btree (chat_id, started_at DESC);

CREATE INDEX ai_runs_generation_idx ON better_supabase.ai_runs USING btree (provider_generation_id)
  WHERE (provider_generation_id IS NOT NULL);

CREATE INDEX ai_runs_owner_idx ON better_supabase.ai_runs USING btree (owner_id);

CREATE INDEX ai_tool_approvals_chat_idx ON better_supabase.ai_tool_approvals USING btree (chat_id);

CREATE INDEX ai_tool_approvals_owner_idx ON better_supabase.ai_tool_approvals USING btree (owner_id);

CREATE INDEX ai_tool_approvals_run_idx ON better_supabase.ai_tool_approvals USING btree (run_id);

CREATE INDEX streams_expires_idx ON better_supabase.streams USING btree (expires_at);

CREATE INDEX streams_owner_idx ON better_supabase.streams USING btree (owner_id);

CREATE INDEX streams_tenant_idx ON better_supabase.streams USING btree (tenant_id);

CREATE POLICY "ai_chats_read" ON "better_supabase"."ai_chats"
  FOR SELECT
  TO "authenticated"
  USING
    (((owner_id = ( SELECT auth.uid() AS uid)) OR ((visibility = 'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.read'::text) AS
    tenant_ids_with)))));

CREATE POLICY "ai_message_feedback_own_read" ON "better_supabase"."ai_message_feedback"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "ai_message_sources_read" ON "better_supabase"."ai_message_sources"
  FOR SELECT
  TO "authenticated"
  USING ((chat_id IN ( SELECT x.id
   FROM better_supabase.ai_chats x)));

CREATE POLICY "ai_messages_read" ON "better_supabase"."ai_messages"
  FOR SELECT
  TO "authenticated"
  USING ((chat_id IN ( SELECT x.id
   FROM better_supabase.ai_chats x)));

CREATE POLICY "ai_pending_inputs_owner_read" ON "better_supabase"."ai_pending_inputs"
  FOR SELECT
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "ai_projects_owner_read" ON "better_supabase"."ai_projects"
  FOR SELECT
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "ai_runs_owner_read" ON "better_supabase"."ai_runs"
  FOR SELECT
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "ai_tool_approvals_owner_read" ON "better_supabase"."ai_tool_approvals"
  FOR SELECT
  TO "authenticated"
  USING ((owner_id = ( SELECT auth.uid() AS uid)));

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

CREATE POLICY "bs_ai_chat_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'ai-chat:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 9) ~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::text) AND better_supabase.ai_chat_can_read((substr(( SELECT realtime.topic() AS topic), 9))::uuid)));

CREATE POLICY "bs_ai_chats_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) = ('ai-chats:'::text || (( SELECT auth.uid() AS uid))::text))));

CREATE POLICY "bs_streams_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'stream:%'::text) AND (EXISTS ( SELECT 1
   FROM better_supabase.streams st
  WHERE ((st.id = substr(( SELECT realtime.topic() AS topic), 8)) AND (st.owner_id = ( SELECT auth.uid() AS uid)))))));

REVOKE ALL ON FUNCTION "api"."ai_chat_can_read"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_chat_can_read"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ai_message_path"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_message_path"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ai_message_siblings"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_message_siblings"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."ai_tool_policies_for"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."ai_tool_policies_for"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."allowed_ai_models"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."allowed_ai_models"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."answer_ai_pending_input"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."answer_ai_pending_input"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."append_ai_user_message"(uuid, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."append_ai_user_message"(uuid, jsonb, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."claim_ai_chat_stream"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_ai_chat_stream"(uuid, text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_ai_chat"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_ai_chat"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."decide_ai_tool_approval"(text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decide_ai_tool_approval"(text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ai_chat"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ai_chat"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ai_project"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ai_project"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_chat"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_chat"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_ai_tool_approvals"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_ai_tool_approvals"(uuid, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_shared_ai_chat"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_shared_ai_chat"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_chat_shares"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_chat_shares"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_moderation_events"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_moderation_events"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_projects"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_projects"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."open_ai_pending_input"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."open_ai_pending_input"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_ai_chats"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_ai_chats"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_streams"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_streams"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."rate_ai_message"(uuid, text, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rate_ai_message"(uuid, text, integer, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_ai_moderation_event"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_ai_moderation_event"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_ai_tool_approval"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_ai_tool_approval"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "api"."request_ai_chat_stop"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_ai_chat_stop"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."revoke_ai_chat_share"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."revoke_ai_chat_share"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."save_ai_project"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_ai_project"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_ai_run_cost"(text, bigint, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_ai_run_cost"(text, bigint, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_ai_tool_policy"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_ai_tool_policy"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."share_ai_chat"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."share_ai_chat"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."stream_append"(text, integer, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stream_append"(text, integer, text[]) TO "service_role";

REVOKE ALL ON FUNCTION "api"."stream_cancel"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stream_cancel"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."stream_close"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stream_close"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."stream_open"(text, uuid, uuid, text, interval, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stream_open"(text, uuid, uuid, text, interval, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."stream_read"(text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stream_read"(text, integer, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."stream_status"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."stream_status"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."switch_ai_branch"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."switch_ai_branch"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_ai_chat"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_ai_chat"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."upsert_ai_models"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."upsert_ai_models"(jsonb, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_chat_can_read"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_chat_can_read"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_chat_notify"(uuid, uuid, text, jsonb, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ai_message_path"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_message_path"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_message_path_of"(uuid, text, boolean) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."ai_message_siblings"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_message_siblings"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ai_tool_policies_for"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ai_tool_policies_for"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."allowed_ai_models"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."allowed_ai_models"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."answer_ai_pending_input"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."answer_ai_pending_input"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."append_ai_user_message"(uuid, jsonb, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."append_ai_user_message"(uuid, jsonb, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_ai_chat_stream"(uuid, text, text, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_ai_chat"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_ai_chat"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decide_ai_tool_approval"(text, boolean, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decide_ai_tool_approval"(text, boolean, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ai_chat"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ai_chat"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ai_project"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ai_project"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_chat"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_chat"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_ai_tool_approvals"(uuid, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_ai_tool_approvals"(uuid, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_shared_ai_chat"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_shared_ai_chat"(text) TO "anon", "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_chat_shares"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_chat_shares"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_chats"(uuid, text, uuid, boolean, boolean, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_moderation_events"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_moderation_events"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_projects"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_projects"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."open_ai_pending_input"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."open_ai_pending_input"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_ai_chats"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_ai_chats"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_streams"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_streams"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rate_ai_message"(uuid, text, integer, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rate_ai_message"(uuid, text, integer, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_ai_moderation_event"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_ai_moderation_event"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_ai_tool_approval"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_ai_tool_approval"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_ai_chat_stream"(uuid, text, text, jsonb, text, text, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_ai_chat_stop"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_ai_chat_stop"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."revoke_ai_chat_share"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."revoke_ai_chat_share"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_ai_assistant_message"(uuid, jsonb, text, text, text, text, jsonb, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_ai_project"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_ai_project"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_ai_run_cost"(text, bigint, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_ai_run_cost"(text, bigint, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_ai_tool_policy"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_ai_tool_policy"(uuid, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."share_ai_chat"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."share_ai_chat"(uuid, text) TO "authenticated", "service_role";

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

REVOKE ALL ON FUNCTION "better_supabase"."switch_ai_branch"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."switch_ai_branch"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_ai_chat"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_ai_chat"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."upsert_ai_models"(jsonb, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."upsert_ai_models"(jsonb, boolean) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_chat_shares" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_chats" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_chats" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_message_feedback" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_message_feedback" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_message_sources" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_message_sources" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_messages" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_messages" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_model_catalog" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_moderation_events" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_pending_inputs" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_pending_inputs" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_projects" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_projects" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_runs" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_runs" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_tool_approvals" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_tool_approvals" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_tool_policies" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."stream_chunks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."stream_chunks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."streams" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."streams" TO "service_role";
