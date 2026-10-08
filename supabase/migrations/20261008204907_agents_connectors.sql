SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."ai_files"
  DROP CONSTRAINT "ai_files_filename_check";

CREATE TABLE "better_supabase"."agent_installs" (
  "agent_id"        uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "installed_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "agent_installs_pkey" PRIMARY KEY (agent_id, user_id, organization_id)
);

ALTER TABLE "better_supabase"."agent_installs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."agent_ratings" (
  "agent_id"   uuid                     NOT NULL,
  "user_id"    uuid                     NOT NULL,
  "rating"     smallint                 NOT NULL,
  "comment"    text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "agent_ratings_comment_check" CHECK ((length(comment) <= 2000)),
  CONSTRAINT "agent_ratings_pkey" PRIMARY KEY (agent_id, user_id),
  CONSTRAINT "agent_ratings_rating_check" CHECK (((rating >= 1) AND (rating <= 5)))
);

ALTER TABLE "better_supabase"."agent_ratings"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."agent_skills" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "agent_id"   uuid                     NOT NULL,
  "provider"   text                     NOT NULL,
  "reference"  jsonb                    NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "agent_skills_pkey" PRIMARY KEY (id),
  CONSTRAINT "agent_skills_provider_check" CHECK (((length(provider) >= 1) AND (length(provider) <= 100))),
  CONSTRAINT "agent_skills_reference_check" CHECK ((jsonb_typeof(reference) = 'object'::text))
);

ALTER TABLE "better_supabase"."agent_skills"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."agents" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "owner_id"        uuid,
  "slug"            text                     NOT NULL,
  "name"            text                     NOT NULL,
  "description"     text                     NOT NULL DEFAULT ''::text,
  "instructions"    text                     NOT NULL DEFAULT ''::text,
  "model"           text,
  "tools"           jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "connector_ids"   uuid[]                   NOT NULL DEFAULT '{}'::uuid[],
  "knowledge_scope" jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "starters"        jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "visibility"      text                     NOT NULL DEFAULT 'private'::text,
  "published_at"    timestamp with time zone,
  "install_count"   integer                  NOT NULL DEFAULT 0,
  "rating_count"    integer                  NOT NULL DEFAULT 0,
  "rating_sum"      integer                  NOT NULL DEFAULT 0,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "agents_description_check" CHECK ((length(description) <= 2000)),
  CONSTRAINT "agents_instructions_check" CHECK ((length(instructions) <= 100000)),
  CONSTRAINT "agents_knowledge_scope_check" CHECK ((jsonb_typeof(knowledge_scope) = 'array'::text)),
  CONSTRAINT "agents_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "agents_organization_id_slug_key" UNIQUE (organization_id, slug),
  CONSTRAINT "agents_pkey" PRIMARY KEY (id),
  CONSTRAINT "agents_slug_check" CHECK (((slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text) AND (length(slug) <= 64))),
  CONSTRAINT "agents_starters_check" CHECK ((jsonb_typeof(starters) = 'array'::text)),
  CONSTRAINT "agents_tools_check" CHECK ((jsonb_typeof(tools) = 'array'::text)),
  CONSTRAINT "agents_visibility_check" CHECK ((visibility = ANY (ARRAY['private'::text, 'organization'::text, 'public'::text])))
);

ALTER TABLE "better_supabase"."agents"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_scheduled_tasks" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "chat_id"         uuid,
  "agent_id"        uuid,
  "title"           text                     NOT NULL,
  "prompt"          text                     NOT NULL,
  "cron"            text                     NOT NULL,
  "timezone"        text                     NOT NULL DEFAULT 'UTC'::text,
  "enabled"         boolean                  NOT NULL DEFAULT true,
  "next_run_at"     timestamp with time zone,
  "last_run_at"     timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_scheduled_tasks_cron_check" CHECK (((length(cron) >= 1) AND (length(cron) <= 200))),
  CONSTRAINT "ai_scheduled_tasks_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_scheduled_tasks_prompt_check" CHECK (((length(prompt) >= 1) AND (length(prompt) <= 20000))),
  CONSTRAINT "ai_scheduled_tasks_timezone_check" CHECK (((length(timezone) >= 1) AND (length(timezone) <= 64))),
  CONSTRAINT "ai_scheduled_tasks_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."ai_scheduled_tasks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."ai_task_runs" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "task_id"         uuid                     NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "user_id"         uuid                     NOT NULL,
  "status"          text                     NOT NULL DEFAULT 'queued'::text,
  "scheduled_for"   timestamp with time zone NOT NULL,
  "chat_id"         uuid,
  "error"           text,
  "started_at"      timestamp with time zone,
  "finished_at"     timestamp with time zone,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_task_runs_error_check" CHECK ((length(error) <= 4000)),
  CONSTRAINT "ai_task_runs_pkey" PRIMARY KEY (id),
  CONSTRAINT "ai_task_runs_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'succeeded'::text, 'failed'::text])))
);

ALTER TABLE "better_supabase"."ai_task_runs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."connector_grants" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "user_id"         uuid                     NOT NULL,
  "server_id"       uuid                     NOT NULL,
  "organization_id" uuid                     NOT NULL,
  "credential_ref"  jsonb                    NOT NULL,
  "scopes"          text[]                   NOT NULL DEFAULT '{}'::text[],
  "expires_at"      timestamp with time zone,
  "granted_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "revoked_at"      timestamp with time zone,
  CONSTRAINT "connector_grants_credential_ref_check" CHECK (((jsonb_typeof(credential_ref) = 'object'::text) AND (credential_ref ? 'provider'::text))),
  CONSTRAINT "connector_grants_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."connector_grants"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."connector_servers" (
  "id"              uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "organization_id" uuid                     NOT NULL,
  "name"            text                     NOT NULL,
  "url"             text                     NOT NULL,
  "transport"       text                     NOT NULL DEFAULT 'http'::text,
  "auth_type"       text                     NOT NULL DEFAULT 'oauth'::text,
  "credential_ref"  jsonb,
  "scopes"          text[]                   NOT NULL DEFAULT '{}'::text[],
  "client_metadata" jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "enabled"         boolean                  NOT NULL DEFAULT true,
  "created_by"      uuid,
  "created_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "connector_servers_auth_type_check" CHECK ((auth_type = ANY (ARRAY['none'::text, 'oauth'::text, 'header'::text]))),
  CONSTRAINT "connector_servers_check" CHECK (((auth_type = 'header'::text) = (credential_ref IS NOT NULL))),
  CONSTRAINT "connector_servers_client_metadata_check" CHECK ((jsonb_typeof(client_metadata) = 'object'::text)),
  CONSTRAINT "connector_servers_credential_ref_check"
    CHECK (((credential_ref IS NULL) OR ((jsonb_typeof(credential_ref) = 'object'::text) AND (credential_ref ? 'provider'::text)))),
  CONSTRAINT "connector_servers_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "connector_servers_pkey" PRIMARY KEY (id),
  CONSTRAINT "connector_servers_transport_check" CHECK ((transport = ANY (ARRAY['http'::text, 'sse'::text]))),
  CONSTRAINT "connector_servers_url_check" CHECK (((url ~ '^(https://|http://(localhost|127[.]0[.]0[.]1)(:[0-9]+)?(/|$))'::text) AND (length(url) <= 2000)))
);

ALTER TABLE "better_supabase"."connector_servers"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."connector_sessions" (
  "server_id"         uuid                     NOT NULL,
  "user_id"           uuid                     NOT NULL,
  "chat_key"          text                     NOT NULL DEFAULT ''::text,
  "session_id"        text,
  "initialize_result" jsonb,
  "last_used_at"      timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"        timestamp with time zone NOT NULL,
  CONSTRAINT "connector_sessions_pkey" PRIMARY KEY (server_id, user_id, chat_key)
);

ALTER TABLE "better_supabase"."connector_sessions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."connector_tool_fingerprints" (
  "server_id"   uuid                     NOT NULL,
  "fingerprint" text                     NOT NULL,
  "tools"       jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "status"      text                     NOT NULL DEFAULT 'pending'::text,
  "approved_by" uuid,
  "approved_at" timestamp with time zone,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "connector_tool_fingerprints_fingerprint_check" CHECK (((length(fingerprint) >= 1) AND (length(fingerprint) <= 200))),
  CONSTRAINT "connector_tool_fingerprints_pkey" PRIMARY KEY (server_id, fingerprint),
  CONSTRAINT "connector_tool_fingerprints_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text]))),
  CONSTRAINT "connector_tool_fingerprints_tools_check" CHECK ((jsonb_typeof(tools) = 'object'::text))
);

ALTER TABLE "better_supabase"."connector_tool_fingerprints"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.check_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  tools       jsonb DEFAULT '{}'::jsonb
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."check_connector_fingerprint"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.claim_due_ai_tasks (
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_due_ai_tasks"($1) $function$;

CREATE OR REPLACE FUNCTION api.decide_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  approved    boolean
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."decide_connector_fingerprint"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.delete_agent (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_agent"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_ai_task (
  id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_ai_task"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_connector_server (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_connector_server"($1) $function$;

CREATE OR REPLACE FUNCTION api.expiring_connector_grants (
  before   timestamp with time zone,
  max_rows integer                  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."expiring_connector_grants"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.finish_ai_task_run (
  id        uuid,
  succeeded boolean,
  error     text    DEFAULT NULL::text,
  chat_id   uuid    DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."finish_ai_task_run"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.get_agent (
  id     uuid DEFAULT NULL::uuid,
  tenant uuid DEFAULT NULL::uuid,
  slug   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_agent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_connector (
  id    uuid,
  owner uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_connector"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_connector_session (
  server_id uuid,
  chat_key  text DEFAULT ''::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_connector_session"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.install_agent (
  tenant    uuid,
  agent_id  uuid,
  installed boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."install_agent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_agents (
  tenant   uuid,
  filter   text    DEFAULT 'store'::text,
  search   text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_agents"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_task_runs (
  task_id  uuid,
  max_rows integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_task_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_ai_tasks (
  tenant uuid,
  mine   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_ai_tasks"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_connector_servers (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_connector_servers"($1) $function$;

CREATE OR REPLACE FUNCTION api.publish_agent (
  id         uuid,
  visibility text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."publish_agent"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_connector_sessions()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_connector_sessions"() $function$;

CREATE OR REPLACE FUNCTION api.rate_agent (
  agent_id uuid,
  rating   integer,
  comment  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rate_agent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.record_connector_grant (
  server_id      uuid,
  owner          uuid,
  credential_ref jsonb,
  scopes         text[]                   DEFAULT '{}'::text[],
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_connector_grant"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.renew_connector_grant (
  id         uuid,
  expires_at timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."renew_connector_grant"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.revoke_connector_grant (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."revoke_connector_grant"($1) $function$;

CREATE OR REPLACE FUNCTION api.save_agent (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_agent"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_ai_task (
  tenant      uuid,
  id          uuid                     DEFAULT NULL::uuid,
  fields      jsonb                    DEFAULT '{}'::jsonb,
  next_run_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_ai_task"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.save_connector_server (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_connector_server"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.save_connector_session (
  server_id         uuid,
  chat_key          text  DEFAULT ''::text,
  session_id        text  DEFAULT NULL::text,
  initialize_result jsonb DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_connector_session"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.schedule_ai_tasks (
  items jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."schedule_ai_tasks"($1) $function$;

CREATE OR REPLACE FUNCTION api.set_agent_skills (
  agent_id uuid,
  skills   jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_agent_skills"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.start_ai_task_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."start_ai_task_run"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.check_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  tools       jsonb DEFAULT '{}'::jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_status text;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = check_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai_chat.create'), false)) then
    raise exception 'connector % not found', check_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select p."status" into v_status from "better_supabase"."connector_tool_fingerprints" p
  where p."server_id" = v_server."id" and p."fingerprint" = check_connector_fingerprint.fingerprint;
  if found then
    return v_status;
  end if;
  v_status := case when exists (select 1 from "better_supabase"."connector_tool_fingerprints" p where p."server_id" = v_server."id") then 'pending' else 'approved' end;
  insert into "better_supabase"."connector_tool_fingerprints" ("server_id", "fingerprint", "tools", "status", "approved_at")
  values (v_server."id", check_connector_fingerprint.fingerprint, coalesce(check_connector_fingerprint.tools, '{}'), v_status,
    case when v_status = 'approved' then now() end)
  on conflict do nothing;
  return v_status;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_due_ai_tasks (
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_runs jsonb := '[]';
  v_unscheduled jsonb;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'failed', "error" = 'timed out', "finished_at" = now()
  where y."status" = 'running' and y."started_at" < now() - interval '30 minutes';
  for v_task in
    select * from "better_supabase"."ai_scheduled_tasks" x
    where x."enabled" and x."next_run_at" <= now()
    order by x."next_run_at"
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into "better_supabase"."ai_task_runs" ("task_id", "organization_id", "user_id", "scheduled_for", "chat_id")
    values (v_task."id", v_task."organization_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    perform "better_supabase"."enqueue_job"(queue => 'ai_task_run', payload => jsonb_build_object('run_id', v_run."id"), dedupe_key => 'ai-task:' || v_run."id"::text, dedupe_running => false);
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'organization_id', v_run."organization_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_for', v_run."scheduled_for", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'cron', x."cron", 'timezone', x."timezone")), '[]')
  into v_unscheduled
  from "better_supabase"."ai_scheduled_tasks" x where x."enabled" and x."next_run_at" is null;
  return jsonb_build_object('runs', v_runs, 'unscheduled', v_unscheduled);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_connector_fingerprint (
  server_id   uuid,
  fingerprint text,
  approved    boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = decide_connector_fingerprint.server_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_server."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'connector % not found', decide_connector_fingerprint.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  update "better_supabase"."connector_tool_fingerprints" p set
    "status" = case when decide_connector_fingerprint.approved then 'approved' else 'rejected' end,
    "approved_by" = auth.uid(), "approved_at" = now()
  where p."server_id" = v_server."id" and p."fingerprint" = decide_connector_fingerprint.fingerprint;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_agent (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x where x."id" = delete_agent.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    return false;
  end if;
  delete from "better_supabase"."agents" x where x."id" = v_row."id";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_ai_task (
  id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := delete_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_connector_server (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
  v_grants jsonb;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = delete_connector_server.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
    raise exception 'connector % not found', delete_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at")), '[]') into v_grants
  from "better_supabase"."connector_grants" y where y."server_id" = v_row."id" and y."revoked_at" is null;
  delete from "better_supabase"."connector_servers" x where x."id" = v_row."id";
  return v_grants;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.expiring_connector_grants (
  before   timestamp with time zone,
  max_rows integer                  DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") order by y."expires_at"), '[]')
  from (
    select * from "better_supabase"."connector_grants" y0
    where y0."revoked_at" is null and y0."expires_at" is not null and y0."expires_at" < expiring_connector_grants.before
    order by y0."expires_at"
    limit least(greatest(expiring_connector_grants.max_rows, 1), 1000)
  ) y
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_ai_task_run (
  id        uuid,
  succeeded boolean,
  error     text    DEFAULT NULL::text,
  chat_id   uuid    DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_task uuid;
begin
  update "better_supabase"."ai_task_runs" y set
    "status" = case when finish_ai_task_run.succeeded then 'succeeded' else 'failed' end,
    "error" = left(finish_ai_task_run.error, 4000),
    "chat_id" = coalesce(finish_ai_task_run.chat_id, y."chat_id"),
    "finished_at" = now()
  where y."id" = finish_ai_task_run.id and y."status" = 'running'
  returning y."task_id" into v_task;
  if not found then
    return false;
  end if;
  if finish_ai_task_run.chat_id is not null then
    update "better_supabase"."ai_scheduled_tasks" x set "chat_id" = finish_ai_task_run.chat_id where x."id" = v_task and x."chat_id" is null;
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_agent (
  id     uuid DEFAULT NULL::uuid,
  tenant uuid DEFAULT NULL::uuid,
  slug   text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  select * into v_row from "better_supabase"."agents" x
  where (get_agent.id is not null and x."id" = get_agent.id)
    or (get_agent.id is null and x."organization_id" = get_agent.tenant and x."slug" = get_agent.slug);
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object(
    'skills', coalesce((select jsonb_agg(jsonb_build_object('id', k."id", 'provider', k."provider", 'reference', k."reference") order by k."created_at") from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id"), '[]'),
    'installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = v_row."id" and n."user_id" = auth.uid()),
    'my_rating', (select g."rating" from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid())
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_connector (
  id    uuid,
  owner uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_user uuid := case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then get_connector.owner else auth.uid() end;
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  select * into v_row from "better_supabase"."connector_servers" x where x."id" = get_connector.id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.read'), false)) then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = v_row."id" and y."user_id" = v_user and y."revoked_at" is null
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_connector_session (
  server_id uuid,
  chat_key  text DEFAULT ''::text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('session_id', z."session_id", 'initialize_result', z."initialize_result", 'expires_at', z."expires_at")
  from "better_supabase"."connector_sessions" z
  where z."server_id" = get_connector_session.server_id and z."user_id" = auth.uid()
    and z."chat_key" = coalesce(get_connector_session.chat_key, '') and z."expires_at" > now()
$function$;

CREATE OR REPLACE FUNCTION better_supabase.install_agent (
  tenant    uuid,
  agent_id  uuid,
  installed boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  if auth.uid() is null or not coalesce(better_supabase.can('tenant', install_agent.tenant, 'ai_chat.read'), false) then
    raise exception 'you may not use agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  if not install_agent.installed then
    delete from "better_supabase"."agent_installs" n where n."agent_id" = install_agent.agent_id and n."user_id" = auth.uid() and n."organization_id" = install_agent.tenant;
    get diagnostics v_count = row_count;
    update "better_supabase"."agents" x set "install_count" = greatest(x."install_count" - v_count, 0) where x."id" = install_agent.agent_id;
    return v_count > 0;
  end if;
  if not exists (select 1 from "better_supabase"."agents" x where x."id" = install_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.moderate')))) then
    raise exception 'agent % not found', install_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  insert into "better_supabase"."agent_installs" ("agent_id", "user_id", "organization_id") values (install_agent.agent_id, auth.uid(), install_agent.tenant)
  on conflict do nothing;
  get diagnostics v_count = row_count;
  update "better_supabase"."agents" x set "install_count" = x."install_count" + v_count where x."id" = install_agent.agent_id;
  return v_count > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_agents (
  tenant   uuid,
  filter   text    DEFAULT 'store'::text,
  search   text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(y.row order by y.at desc), '[]')
  from (
    select jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'owner_id', x."owner_id", 'slug', x."slug", 'name', x."name", 'description', x."description", 'instructions', x."instructions", 'model', x."model", 'tools', x."tools", 'connector_ids', x."connector_ids", 'knowledge_scope', x."knowledge_scope", 'starters', x."starters", 'visibility', x."visibility", 'published_at', x."published_at", 'install_count', x."install_count", 'rating_count', x."rating_count", 'rating_sum', x."rating_sum", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('installed', exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."organization_id" = list_agents.tenant)) as row,
      coalesce(x."published_at", x."updated_at") as at
    from "better_supabase"."agents" x
    where case list_agents.filter
        when 'mine' then x."owner_id" = auth.uid() and x."organization_id" = list_agents.tenant
        when 'installed' then exists (select 1 from "better_supabase"."agent_installs" n where n."agent_id" = x."id" and n."user_id" = auth.uid() and n."organization_id" = list_agents.tenant)
        else x."published_at" is not null and (x."visibility" = 'public' or x."organization_id" = list_agents.tenant)
      end
      and (list_agents.search is null or x."name" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%'
        or x."description" ilike '%' || replace(replace(list_agents.search, '%', '\%'), '_', '\_') || '%')
    order by coalesce(x."published_at", x."updated_at") desc
    limit least(greatest(list_agents.max_rows, 1), 200)
  ) y
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_task_runs (
  task_id  uuid,
  max_rows integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'organization_id', y."organization_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_for', y."scheduled_for", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
  from (
    select * from "better_supabase"."ai_task_runs" y0 where y0."task_id" = list_ai_task_runs.task_id
    order by y0."created_at" desc limit least(greatest(list_ai_task_runs.max_rows, 1), 200)
  ) y
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_ai_tasks (
  tenant uuid,
  mine   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'organization_id', y."organization_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_for', y."scheduled_for", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."organization_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_connector_servers (
  tenant uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'name', x."name", 'url', x."url", 'transport', x."transport", 'auth_type', x."auth_type", 'credential_ref', x."credential_ref", 'scopes', x."scopes", 'client_metadata', x."client_metadata", 'enabled', x."enabled", 'created_by', x."created_by", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('grant', (
    select jsonb_build_object('id', y."id", 'user_id', y."user_id", 'server_id', y."server_id", 'organization_id', y."organization_id", 'credential_ref', y."credential_ref", 'scopes', y."scopes", 'expires_at', y."expires_at", 'granted_at', y."granted_at", 'revoked_at', y."revoked_at") from "better_supabase"."connector_grants" y
    where y."server_id" = x."id" and y."user_id" = auth.uid() and y."revoked_at" is null
  )) order by x."name"), '[]')
  from "better_supabase"."connector_servers" x where x."organization_id" = list_connector_servers.tenant
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_agent (
  id         uuid,
  visibility text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if publish_agent.visibility is null or publish_agent.visibility not in ('private', 'organization', 'public') then
    raise exception 'visibility is private, organization or public' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = publish_agent.id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    raise exception 'agent % not found', publish_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if publish_agent.visibility <> 'private' and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)
    or (v_row."owner_id" = auth.uid() and coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.share'), false))) then
    raise exception 'you may not publish agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."agents" x set
    "visibility" = publish_agent.visibility,
    "published_at" = case when publish_agent.visibility = 'private' then null else coalesce(x."published_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_connector_sessions()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."connector_sessions" z where z."expires_at" < now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rate_agent (
  agent_id uuid,
  rating   integer,
  comment  text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_old integer;
  v_row "better_supabase"."agents"%rowtype;
begin
  if auth.uid() is null then
    raise exception 'sign in to rate agents' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."agents" x where x."id" = rate_agent.agent_id and (x."owner_id" = (select auth.uid()) or (x."published_at" is not null and (x."visibility" = 'public' or (x."visibility" = 'organization' and x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.read'))))) or x."organization_id" in (select better_supabase.tenant_ids_with('ai_chat.moderate'))) for update;
  if not found then
    raise exception 'agent % not found', rate_agent.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if rate_agent.rating is not null and rate_agent.rating not between 1 and 5 then
    raise exception 'a rating is 1 to 5' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_ratings" g where g."agent_id" = v_row."id" and g."user_id" = auth.uid()
  returning g."rating" into v_old;
  if rate_agent.rating is not null then
    insert into "better_supabase"."agent_ratings" ("agent_id", "user_id", "rating", "comment")
    values (v_row."id", auth.uid(), rate_agent.rating, rate_agent.comment);
  end if;
  update "better_supabase"."agents" x set
    "rating_count" = x."rating_count" - (case when v_old is null then 0 else 1 end) + (case when rate_agent.rating is null then 0 else 1 end),
    "rating_sum" = x."rating_sum" - coalesce(v_old, 0) + coalesce(rate_agent.rating, 0)
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_connector_grant (
  server_id      uuid,
  owner          uuid,
  credential_ref jsonb,
  scopes         text[]                   DEFAULT '{}'::text[],
  expires_at     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_server "better_supabase"."connector_servers"%rowtype;
  v_old "better_supabase"."connector_grants"%rowtype;
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  select * into v_server from "better_supabase"."connector_servers" x where x."id" = record_connector_grant.server_id;
  if not found then
    raise exception 'connector % not found', record_connector_grant.server_id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
  end if;
  if not coalesce(better_supabase.member_can(record_connector_grant.owner, v_server."organization_id", 'ai_chat.create'), false) then
    raise exception 'the user may not use connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."server_id" = v_server."id" and y."user_id" = record_connector_grant.owner and y."revoked_at" is null
  returning * into v_old;
  insert into "better_supabase"."connector_grants" ("user_id", "server_id", "organization_id", "credential_ref", "scopes", "expires_at")
  values (record_connector_grant.owner, v_server."id", v_server."organization_id", record_connector_grant.credential_ref,
    coalesce(record_connector_grant.scopes, '{}'), record_connector_grant.expires_at)
  returning * into v_row;
  return jsonb_build_object('grant', jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at"), 'replaced', case when v_old."id" is null then null else jsonb_build_object('id', v_old."id", 'user_id', v_old."user_id", 'server_id', v_old."server_id", 'organization_id', v_old."organization_id", 'credential_ref', v_old."credential_ref", 'scopes', v_old."scopes", 'expires_at', v_old."expires_at", 'granted_at', v_old."granted_at", 'revoked_at', v_old."revoked_at") end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.renew_connector_grant (
  id         uuid,
  expires_at timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with updated as (
    update "better_supabase"."connector_grants" y set "expires_at" = renew_connector_grant.expires_at
    where y."id" = renew_connector_grant.id and y."revoked_at" is null
    returning 1
  )
  select exists (select 1 from updated)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.revoke_connector_grant (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_grants"%rowtype;
begin
  update "better_supabase"."connector_grants" y set "revoked_at" = now()
  where y."id" = revoke_connector_grant.id and y."revoked_at" is null
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or y."user_id" = auth.uid())
  returning * into v_row;
  if not found then
    return null;
  end if;
  delete from "better_supabase"."connector_sessions" z where z."server_id" = v_row."server_id" and z."user_id" = v_row."user_id";
  return jsonb_build_object('id', v_row."id", 'user_id', v_row."user_id", 'server_id', v_row."server_id", 'organization_id', v_row."organization_id", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'expires_at', v_row."expires_at", 'granted_at', v_row."granted_at", 'revoked_at', v_row."revoked_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_agent (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
begin
  if jsonb_typeof(save_agent.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  if save_agent.id is null then
    if auth.uid() is null or not coalesce(better_supabase.can('tenant', save_agent.tenant, 'ai_chat.create'), false) then
      raise exception 'you may not create agents here' using errcode = '42501', hint = 'AGENT_FORBIDDEN';
    end if;
    if save_agent.fields ->> 'slug' is null or save_agent.fields ->> 'name' is null then
      raise exception 'a new agent needs a slug and a name' using errcode = '22023', hint = 'AGENT_INVALID';
    end if;
    insert into "better_supabase"."agents" ("organization_id", "owner_id", "slug", "name")
    values (save_agent.tenant, auth.uid(), save_agent.fields ->> 'slug', save_agent.fields ->> 'name')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."agents" x where x."id" = save_agent.id and x."organization_id" = save_agent.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
      raise exception 'agent % not found', save_agent.id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."agents" x set
    "slug" = coalesce(save_agent.fields ->> 'slug', x."slug"),
    "name" = coalesce(save_agent.fields ->> 'name', x."name"),
    "description" = coalesce(save_agent.fields ->> 'description', x."description"),
    "instructions" = coalesce(save_agent.fields ->> 'instructions', x."instructions"),
    "model" = case when save_agent.fields ? 'model' then save_agent.fields ->> 'model' else x."model" end,
    "tools" = coalesce(save_agent.fields -> 'tools', x."tools"),
    "connector_ids" = case when save_agent.fields ? 'connector_ids'
      then array(select jsonb_array_elements_text(save_agent.fields -> 'connector_ids')::uuid)
      else x."connector_ids" end,
    "knowledge_scope" = coalesce(save_agent.fields -> 'knowledge_scope', x."knowledge_scope"),
    "starters" = coalesce(save_agent.fields -> 'starters', x."starters"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'owner_id', v_row."owner_id", 'slug', v_row."slug", 'name', v_row."name", 'description', v_row."description", 'instructions', v_row."instructions", 'model', v_row."model", 'tools', v_row."tools", 'connector_ids', v_row."connector_ids", 'knowledge_scope', v_row."knowledge_scope", 'starters', v_row."starters", 'visibility', v_row."visibility", 'published_at', v_row."published_at", 'install_count', v_row."install_count", 'rating_count', v_row."rating_count", 'rating_sum', v_row."rating_sum", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
exception
  when unique_violation then
    raise exception 'an agent with slug % exists', save_agent.fields ->> 'slug' using errcode = '23505', hint = 'AGENT_SLUG_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_ai_task (
  tenant      uuid,
  id          uuid                     DEFAULT NULL::uuid,
  fields      jsonb                    DEFAULT '{}'::jsonb,
  next_run_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid := save_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  if jsonb_typeof(save_ai_task.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if v_id is null then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_chat.create'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("organization_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."organization_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.admin'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."ai_scheduled_tasks" x set
    "title" = coalesce(save_ai_task.fields ->> 'title', x."title"),
    "prompt" = coalesce(save_ai_task.fields ->> 'prompt', x."prompt"),
    "cron" = coalesce(save_ai_task.fields ->> 'cron', x."cron"),
    "timezone" = coalesce(save_ai_task.fields ->> 'timezone', x."timezone"),
    "chat_id" = case when save_ai_task.fields ? 'chat_id' then (save_ai_task.fields ->> 'chat_id')::uuid else x."chat_id" end,
    "agent_id" = case when save_ai_task.fields ? 'agent_id' then (save_ai_task.fields ->> 'agent_id')::uuid else x."agent_id" end,
    "enabled" = coalesce((save_ai_task.fields ->> 'enabled')::boolean, x."enabled"),
    "next_run_at" = case when (save_ai_task.fields ->> 'enabled')::boolean is false then null when save_ai_task.next_run_at is not null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone' then save_ai_task.next_run_at else x."next_run_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_connector_server (
  tenant uuid,
  id     uuid  DEFAULT NULL::uuid,
  fields jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."connector_servers"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_connector_server.tenant, 'ai_chat.admin'), false)) then
    raise exception 'you may not manage connectors here' using errcode = '42501', hint = 'CONNECTOR_FORBIDDEN';
  end if;
  if jsonb_typeof(save_connector_server.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CONNECTOR_INVALID';
  end if;
  if save_connector_server.id is null then
    insert into "better_supabase"."connector_servers" ("organization_id", "name", "url", "auth_type", "credential_ref", "created_by")
    values (save_connector_server.tenant, save_connector_server.fields ->> 'name', save_connector_server.fields ->> 'url',
      coalesce(save_connector_server.fields ->> 'auth_type', 'oauth'), save_connector_server.fields -> 'credential_ref', auth.uid())
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."connector_servers" x where x."id" = save_connector_server.id and x."organization_id" = save_connector_server.tenant for update;
    if not found then
      raise exception 'connector % not found', save_connector_server.id using errcode = 'P0002', hint = 'CONNECTOR_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."connector_servers" x set
    "name" = coalesce(save_connector_server.fields ->> 'name', x."name"),
    "url" = coalesce(save_connector_server.fields ->> 'url', x."url"),
    "transport" = coalesce(save_connector_server.fields ->> 'transport', x."transport"),
    "auth_type" = coalesce(save_connector_server.fields ->> 'auth_type', x."auth_type"),
    "credential_ref" = case when save_connector_server.fields ? 'credential_ref' then nullif(save_connector_server.fields -> 'credential_ref', 'null') else x."credential_ref" end,
    "scopes" = case when save_connector_server.fields ? 'scopes' then array(select jsonb_array_elements_text(save_connector_server.fields -> 'scopes')) else x."scopes" end,
    "client_metadata" = coalesce(save_connector_server.fields -> 'client_metadata', x."client_metadata"),
    "enabled" = coalesce((save_connector_server.fields ->> 'enabled')::boolean, x."enabled"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'name', v_row."name", 'url', v_row."url", 'transport', v_row."transport", 'auth_type', v_row."auth_type", 'credential_ref', v_row."credential_ref", 'scopes', v_row."scopes", 'client_metadata', v_row."client_metadata", 'enabled', v_row."enabled", 'created_by', v_row."created_by", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_connector_session (
  server_id         uuid,
  chat_key          text  DEFAULT ''::text,
  session_id        text  DEFAULT NULL::text,
  initialize_result jsonb DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  if auth.uid() is null then
    return false;
  end if;
  if save_connector_session.session_id is null and save_connector_session.initialize_result is null then
    delete from "better_supabase"."connector_sessions" z where z."server_id" = save_connector_session.server_id and z."user_id" = auth.uid()
      and z."chat_key" = coalesce(save_connector_session.chat_key, '');
    return true;
  end if;
  if not exists (select 1 from "better_supabase"."connector_grants" y where y."server_id" = save_connector_session.server_id and y."user_id" = auth.uid() and y."revoked_at" is null)
    and not exists (select 1 from "better_supabase"."connector_servers" x where x."id" = save_connector_session.server_id and x."auth_type" <> 'oauth' and coalesce(better_supabase.can('tenant', x."organization_id", 'ai_chat.create'), false)) then
    return false;
  end if;
  insert into "better_supabase"."connector_sessions" ("server_id", "user_id", "chat_key", "session_id", "initialize_result", "expires_at")
  values (save_connector_session.server_id, auth.uid(), coalesce(save_connector_session.chat_key, ''), save_connector_session.session_id,
    save_connector_session.initialize_result, now() + interval '1 hour')
  on conflict ("server_id", "user_id", "chat_key") do update set
    "session_id" = excluded."session_id", "initialize_result" = excluded."initialize_result",
    "last_used_at" = now(), "expires_at" = excluded."expires_at";
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_ai_tasks (
  items jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_items jsonb := case when jsonb_typeof(schedule_ai_tasks.items) = 'object' then schedule_ai_tasks.items -> 'items' else schedule_ai_tasks.items end;
  v_count integer;
begin
  update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = (item ->> 'next_run_at')::timestamptz
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  where x."id" = (item ->> 'id')::uuid;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_agent_skills (
  agent_id uuid,
  skills   jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."agents"%rowtype;
  v_items jsonb := case when jsonb_typeof(set_agent_skills.skills) = 'object' then set_agent_skills.skills -> 'items' else set_agent_skills.skills end;
  v_count integer;
begin
  select * into v_row from "better_supabase"."agents" x where x."id" = set_agent_skills.agent_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."owner_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai_chat.moderate'), false)) then
    raise exception 'agent % not found', set_agent_skills.agent_id using errcode = 'P0002', hint = 'AGENT_NOT_FOUND';
  end if;
  if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'skills must be a list' using errcode = '22023', hint = 'AGENT_INVALID';
  end if;
  delete from "better_supabase"."agent_skills" k where k."agent_id" = v_row."id";
  insert into "better_supabase"."agent_skills" ("agent_id", "provider", "reference")
  select v_row."id", e ->> 'provider', e -> 'reference' from jsonb_array_elements(v_items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_ai_task_run (
  id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'running', "started_at" = now()
  where y."id" = start_ai_task_run.id and y."status" = 'queued'
  returning * into v_run;
  if not found then
    return null;
  end if;
  select * into v_task from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_run."task_id";
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'organization_id', v_run."organization_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_for', v_run."scheduled_for", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'organization_id', v_task."organization_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
end;
$function$;

ALTER TABLE "better_supabase"."agent_installs"
  ADD CONSTRAINT "agent_installs_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."agent_ratings"
  ADD CONSTRAINT "agent_ratings_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."agents"
  ADD CONSTRAINT "agents_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."agent_installs"
  ADD CONSTRAINT "agent_installs_agent_id_fkey" FOREIGN KEY (agent_id) REFERENCES better_supabase.agents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."agent_ratings"
  ADD CONSTRAINT "agent_ratings_agent_id_fkey" FOREIGN KEY (agent_id) REFERENCES better_supabase.agents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."agent_skills"
  ADD CONSTRAINT "agent_skills_agent_id_fkey" FOREIGN KEY (agent_id) REFERENCES better_supabase.agents(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_files"
  ADD CONSTRAINT "ai_files_filename_check"
    CHECK ((((length(filename) >= 1) AND (length(filename) <= 255)) AND (filename !~ '[/\\]'::text) AND (filename <> ALL (ARRAY['.'::text, '..'::text]))));

ALTER TABLE "better_supabase"."ai_scheduled_tasks"
  ADD CONSTRAINT "ai_scheduled_tasks_agent_id_fkey" FOREIGN KEY (agent_id) REFERENCES better_supabase.agents(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."ai_scheduled_tasks"
  ADD CONSTRAINT "ai_scheduled_tasks_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_task_runs"
  ADD CONSTRAINT "ai_task_runs_task_id_fkey" FOREIGN KEY (task_id) REFERENCES better_supabase.ai_scheduled_tasks(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."ai_task_runs"
  ADD CONSTRAINT "ai_task_runs_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."connector_grants"
  ADD CONSTRAINT "connector_grants_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."connector_servers"
  ADD CONSTRAINT "connector_servers_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."connector_grants"
  ADD CONSTRAINT "connector_grants_server_id_fkey" FOREIGN KEY (server_id) REFERENCES better_supabase.connector_servers(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."connector_sessions"
  ADD CONSTRAINT "connector_sessions_server_id_fkey" FOREIGN KEY (server_id) REFERENCES better_supabase.connector_servers(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."connector_sessions"
  ADD CONSTRAINT "connector_sessions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."connector_tool_fingerprints"
  ADD CONSTRAINT "connector_tool_fingerprints_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."connector_tool_fingerprints"
  ADD CONSTRAINT "connector_tool_fingerprints_server_id_fkey" FOREIGN KEY (server_id) REFERENCES better_supabase.connector_servers(id) ON DELETE CASCADE;

CREATE INDEX agent_installs_user_idx ON better_supabase.agent_installs USING btree (user_id, organization_id);

CREATE INDEX agent_ratings_user_idx ON better_supabase.agent_ratings USING btree (user_id);

CREATE INDEX agent_skills_agent_idx ON better_supabase.agent_skills USING btree (agent_id);

CREATE INDEX agents_owner_idx ON better_supabase.agents USING btree (owner_id);

CREATE INDEX agents_published_idx ON better_supabase.agents USING btree (visibility, published_at)
  WHERE (published_at IS NOT NULL);

CREATE INDEX ai_scheduled_tasks_agent_idx ON better_supabase.ai_scheduled_tasks USING btree (agent_id);

CREATE INDEX ai_scheduled_tasks_due_idx ON better_supabase.ai_scheduled_tasks USING btree (next_run_at)
  WHERE enabled;

CREATE INDEX ai_scheduled_tasks_user_idx ON better_supabase.ai_scheduled_tasks USING btree (user_id, organization_id);

CREATE INDEX ai_task_runs_open_idx ON better_supabase.ai_task_runs USING btree (status, started_at)
  WHERE (status = ANY (ARRAY['queued'::text, 'running'::text]));

CREATE INDEX ai_task_runs_task_idx ON better_supabase.ai_task_runs USING btree (task_id, created_at DESC);

CREATE INDEX ai_task_runs_user_idx ON better_supabase.ai_task_runs USING btree (user_id);

CREATE UNIQUE INDEX connector_grants_active_idx ON better_supabase.connector_grants USING btree (user_id, server_id)
  WHERE (revoked_at IS NULL);

CREATE INDEX connector_grants_server_idx ON better_supabase.connector_grants USING btree (server_id);

CREATE INDEX connector_grants_user_idx ON better_supabase.connector_grants USING btree (user_id);

CREATE INDEX connector_servers_created_by_idx ON better_supabase.connector_servers USING btree (created_by);

CREATE INDEX connector_servers_tenant_idx ON better_supabase.connector_servers USING btree (organization_id);

CREATE INDEX connector_sessions_expires_idx ON better_supabase.connector_sessions USING btree (expires_at);

CREATE INDEX connector_sessions_user_idx ON better_supabase.connector_sessions USING btree (user_id);

CREATE INDEX connector_tool_fingerprints_approved_by_idx ON better_supabase.connector_tool_fingerprints USING btree (approved_by);

CREATE POLICY "agent_installs_read" ON "better_supabase"."agent_installs"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "agent_ratings_read" ON "better_supabase"."agent_ratings"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.agents x
  WHERE (x.id = agent_ratings.agent_id))));

CREATE POLICY "agent_skills_read" ON "better_supabase"."agent_skills"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.agents x
  WHERE (x.id = agent_skills.agent_id))));

CREATE POLICY "agents_read" ON "better_supabase"."agents"
  FOR SELECT
  TO "authenticated"
  USING (((owner_id = ( SELECT auth.uid() AS uid)) OR ((published_at IS
    NOT NULL) AND
    ((visibility = 'public'::text) OR ((visibility = 'organization'::text) AND (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.read'::text) AS
    tenant_ids_with))))) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.moderate'::text) AS tenant_ids_with))));

CREATE POLICY "ai_scheduled_tasks_read" ON "better_supabase"."ai_scheduled_tasks"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with))));

CREATE POLICY "ai_task_runs_read" ON "better_supabase"."ai_task_runs"
  FOR SELECT
  TO "authenticated"
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.admin'::text) AS tenant_ids_with))));

CREATE POLICY "connector_grants_read" ON "better_supabase"."connector_grants"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "connector_servers_read" ON "better_supabase"."connector_servers"
  FOR SELECT
  TO "authenticated"
  USING ((organization_id IN ( SELECT better_supabase.tenant_ids_with('ai_chat.read'::text) AS tenant_ids_with)));

CREATE POLICY "connector_sessions_read" ON "better_supabase"."connector_sessions"
  FOR SELECT
  TO "authenticated"
  USING ((user_id = ( SELECT auth.uid() AS uid)));

CREATE POLICY "connector_tool_fingerprints_read" ON "better_supabase"."connector_tool_fingerprints"
  FOR SELECT
  TO "authenticated"
  USING ((EXISTS ( SELECT 1
   FROM better_supabase.connector_servers x
  WHERE (x.id = connector_tool_fingerprints.server_id))));

REVOKE ALL ON FUNCTION "api"."check_connector_fingerprint"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."check_connector_fingerprint"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."claim_due_ai_tasks"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_due_ai_tasks"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."decide_connector_fingerprint"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."decide_connector_fingerprint"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_agent"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_ai_task"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_ai_task"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_connector_server"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_connector_server"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."expiring_connector_grants"(timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."expiring_connector_grants"(timestamp WITH time zone, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."finish_ai_task_run"(uuid, boolean, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."finish_ai_task_run"(uuid, boolean, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_agent"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_agent"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_connector"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_connector"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."get_connector_session"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_connector_session"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."install_agent"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."install_agent"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_agents"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_agents"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_task_runs"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_task_runs"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_ai_tasks"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_ai_tasks"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_connector_servers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_connector_servers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."publish_agent"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."publish_agent"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_connector_sessions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_connector_sessions"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."rate_agent"(uuid, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rate_agent"(uuid, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."renew_connector_grant"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."renew_connector_grant"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."revoke_connector_grant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."revoke_connector_grant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_agent"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_agent"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_ai_task"(uuid, uuid, jsonb, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_ai_task"(uuid, uuid, jsonb, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_connector_server"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_connector_server"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_connector_session"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_connector_session"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."schedule_ai_tasks"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."schedule_ai_tasks"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_agent_skills"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_agent_skills"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."start_ai_task_run"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."start_ai_task_run"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."check_connector_fingerprint"(uuid, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_due_ai_tasks"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_due_ai_tasks"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."decide_connector_fingerprint"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_agent"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_agent"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_ai_task"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_ai_task"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_connector_server"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_connector_server"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."expiring_connector_grants"(timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."expiring_connector_grants"(timestamp WITH time zone, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."finish_ai_task_run"(uuid, boolean, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."finish_ai_task_run"(uuid, boolean, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_agent"(uuid, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_agent"(uuid, uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_connector"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_connector"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_connector_session"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_connector_session"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."install_agent"(uuid, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."install_agent"(uuid, uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_agents"(uuid, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_agents"(uuid, text, text, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_task_runs"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_task_runs"(uuid, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_ai_tasks"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_ai_tasks"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_connector_servers"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_connector_servers"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."publish_agent"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."publish_agent"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_connector_sessions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_connector_sessions"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rate_agent"(uuid, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rate_agent"(uuid, integer, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_connector_grant"(uuid, uuid, jsonb, text[], timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."renew_connector_grant"(uuid, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."renew_connector_grant"(uuid, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."revoke_connector_grant"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."revoke_connector_grant"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_agent"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_agent"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_ai_task"(uuid, uuid, jsonb, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_ai_task"(uuid, uuid, jsonb, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_connector_server"(uuid, uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_connector_server"(uuid, uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_connector_session"(uuid, text, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_connector_session"(uuid, text, text, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."schedule_ai_tasks"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."schedule_ai_tasks"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_agent_skills"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_agent_skills"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."start_ai_task_run"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."start_ai_task_run"(uuid) TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."agent_installs" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."agent_installs" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."agent_ratings" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."agent_ratings" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."agent_skills" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."agent_skills" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."agents" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."agents" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_scheduled_tasks" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_scheduled_tasks" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."ai_task_runs" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."ai_task_runs" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."connector_grants" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."connector_grants" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."connector_servers" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."connector_servers" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."connector_sessions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."connector_sessions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."connector_tool_fingerprints" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."connector_tool_fingerprints" TO "service_role";
