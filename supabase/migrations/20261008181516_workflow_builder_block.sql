SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."workflow_alert_fires" (
  "alert_id" uuid                     NOT NULL,
  "run_id"   uuid                     NOT NULL,
  "fired_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_alert_fires_pkey" PRIMARY KEY (alert_id, run_id)
);

ALTER TABLE "better_supabase"."workflow_alert_fires"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_alerts" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "definition_id" uuid                     NOT NULL,
  "on_event"      text                     NOT NULL,
  "threshold"     interval,
  "channel"       jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "created_by"    uuid,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_alerts_on_event_check" CHECK ((on_event = ANY (ARRAY['failed'::text, 'slow'::text]))),
  CONSTRAINT "workflow_alerts_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_alerts_threshold_check" CHECK (((on_event <> 'slow'::text) OR (threshold > '00:00:00'::interval)))
);

ALTER TABLE "better_supabase"."workflow_alerts"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_credentials" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"      uuid,
  "kind"           text                     NOT NULL,
  "name"           text                     NOT NULL,
  "credential_ref" jsonb                    NOT NULL,
  "scopes"         text[]                   NOT NULL DEFAULT '{}'::text[],
  "created_by"     uuid,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_credentials_credential_ref_check" CHECK ((jsonb_typeof((credential_ref -> 'provider'::text)) = 'string'::text)),
  CONSTRAINT "workflow_credentials_kind_check" CHECK (((length(kind) >= 1) AND (length(kind) <= 100))),
  CONSTRAINT "workflow_credentials_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "workflow_credentials_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_credentials_tenant_name_key" UNIQUE NULLS NOT DISTINCT (tenant_id, name)
);

ALTER TABLE "better_supabase"."workflow_credentials"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_definitions" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid,
  "slug"        text                     NOT NULL,
  "name"        text                     NOT NULL,
  "description" text,
  "created_by"  uuid,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_definitions_description_check" CHECK ((length(description) <= 2000)),
  CONSTRAINT "workflow_definitions_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "workflow_definitions_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_definitions_slug_check" CHECK ((slug ~ '^[a-z0-9][a-z0-9-]{0,99}$'::text)),
  CONSTRAINT "workflow_definitions_tenant_slug_key" UNIQUE NULLS NOT DISTINCT (tenant_id, slug)
);

ALTER TABLE "better_supabase"."workflow_definitions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_node_runs" (
  "run_id"     uuid                     NOT NULL,
  "node_id"    text                     NOT NULL,
  "status"     text                     NOT NULL,
  "attempts"   integer                  NOT NULL DEFAULT 0,
  "output"     jsonb,
  "error"      text,
  "started_at" timestamp with time zone,
  "ended_at"   timestamp with time zone,
  CONSTRAINT "workflow_node_runs_node_id_check" CHECK (((length(node_id) >= 1) AND (length(node_id) <= 100))),
  CONSTRAINT "workflow_node_runs_pkey" PRIMARY KEY (run_id, node_id),
  CONSTRAINT "workflow_node_runs_status_check" CHECK ((status = ANY (ARRAY['running'::text, 'waiting'::text, 'completed'::text, 'failed'::text, 'skipped'::text])))
);

ALTER TABLE "better_supabase"."workflow_node_runs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_step_library" (
  "name"            text                     NOT NULL,
  "title"           text                     NOT NULL,
  "description"     text,
  "input_schema"    jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "output_schema"   jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "credential_kind" text,
  "updated_at"      timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_step_library_name_check" CHECK ((name ~ '^[A-Za-z][A-Za-z0-9_.-]{0,99}$'::text)),
  CONSTRAINT "workflow_step_library_pkey" PRIMARY KEY (name),
  CONSTRAINT "workflow_step_library_title_check" CHECK (((length(title) >= 1) AND (length(title) <= 200)))
);

ALTER TABLE "better_supabase"."workflow_step_library"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_triggers" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "definition_id" uuid                     NOT NULL,
  "kind"          text                     NOT NULL,
  "config"        jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "enabled"       boolean                  NOT NULL DEFAULT true,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_triggers_kind_check" CHECK ((kind = ANY (ARRAY['manual'::text, 'webhook'::text, 'schedule'::text, 'event'::text, 'form'::text, 'chat'::text]))),
  CONSTRAINT "workflow_triggers_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."workflow_triggers"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_versions" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "definition_id" uuid                     NOT NULL,
  "version"       integer                  NOT NULL,
  "graph"         jsonb                    NOT NULL DEFAULT '{"edges": [], "nodes": []}'::jsonb,
  "compiled"      jsonb,
  "status"        text                     NOT NULL DEFAULT 'draft'::text,
  "created_by"    uuid,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "published_at"  timestamp with time zone,
  CONSTRAINT "workflow_versions_definition_version_key" UNIQUE (definition_id, VERSION),
  CONSTRAINT "workflow_versions_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_versions_status_check" CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'archived'::text]))),
  CONSTRAINT "workflow_versions_version_check" CHECK ((version > 0))
);

ALTER TABLE "better_supabase"."workflow_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_webhook_tokens" (
  "token_hash" bytea                    NOT NULL,
  "trigger_id" uuid                     NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_webhook_tokens_pkey" PRIMARY KEY (token_hash),
  CONSTRAINT "workflow_webhook_tokens_trigger_id_key" UNIQUE (trigger_id)
);

ALTER TABLE "better_supabase"."workflow_webhook_tokens"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.check_workflow_alerts (
  batch integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."check_workflow_alerts"($1) $function$;

CREATE OR REPLACE FUNCTION api.publish_workflow_version (
  version  uuid,
  compiled jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."publish_workflow_version"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_workflow_node_run (
  run     text,
  node    text,
  status  text,
  attempt integer DEFAULT NULL::integer,
  output  jsonb   DEFAULT NULL::jsonb,
  error   text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_workflow_node_run"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.remove_workflow_alert (
  alert uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_workflow_alert"($1) $function$;

CREATE OR REPLACE FUNCTION api.remove_workflow_credential (
  credential uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_workflow_credential"($1) $function$;

CREATE OR REPLACE FUNCTION api.remove_workflow_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_workflow_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.remove_workflow_trigger (
  trigger uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_workflow_trigger"($1) $function$;

CREATE OR REPLACE FUNCTION api.rotate_workflow_webhook_token (
  trigger uuid
)
  RETURNS text
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."rotate_workflow_webhook_token"($1) $function$;

CREATE OR REPLACE FUNCTION api.save_workflow_alert (
  definition uuid,
  on_event   text,
  channel    jsonb    DEFAULT '{}'::jsonb,
  threshold  interval DEFAULT NULL::interval,
  alert      uuid     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_workflow_alert"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_workflow_credential (
  tenant uuid,
  kind   text,
  name   text,
  ref    jsonb,
  scopes text[] DEFAULT '{}'::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_workflow_credential"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.save_workflow_definition (
  tenant      uuid,
  slug        text,
  name        text,
  description text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_workflow_definition"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.save_workflow_draft (
  definition uuid,
  graph      jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_workflow_draft"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.save_workflow_trigger (
  definition uuid,
  kind       text,
  config     jsonb   DEFAULT '{}'::jsonb,
  enabled    boolean DEFAULT true,
  trigger    uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."save_workflow_trigger"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.sync_workflow_steps (
  steps jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."sync_workflow_steps"($1) $function$;

CREATE OR REPLACE FUNCTION api.validate_workflow_graph (
  graph jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."validate_workflow_graph"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_alerts_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_alerts_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_credential_get (
  credential uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_credential_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_credentials_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_credentials_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_definition_get (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_definition_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_definitions_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_definitions_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_event_targets (
  type   text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_event_targets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.workflow_node_runs_list (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_node_runs_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_start_target (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_start_target"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_steps_list()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_steps_list"() $function$;

CREATE OR REPLACE FUNCTION api.workflow_triggers_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_triggers_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_version_get (
  version uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_version_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_versions_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_versions_list"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_webhook_target (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_webhook_target"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.check_workflow_alerts (
  batch integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_pair record;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_run "better_supabase"."workflow_runs"%rowtype;
  v_fired integer := 0;
begin
  for v_pair in
    select x."id" as alert, y."id" as run from "better_supabase"."workflow_alerts" x
    join "better_supabase"."workflow_runs" y on y."attributes" ->> 'bs.definition' = x."definition_id"::text
    where x."on_event" = 'slow'
      and y."status" in ('queued', 'running', 'waiting')
      and y."created_at" < now() - x."threshold"
      and not exists (select 1 from "better_supabase"."workflow_alert_fires" z where z."alert_id" = x."id" and z."run_id" = y."id")
    limit greatest(coalesce(batch, 100), 1)
  loop
    select * into v_alert from "better_supabase"."workflow_alerts" x where x."id" = v_pair.alert;
    select * into v_run from "better_supabase"."workflow_runs" x where x."id" = v_pair.run;
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
      end if;
  end loop;
  return v_fired;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.publish_workflow_version (
  version  uuid,
  compiled jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_versions"%rowtype;
  v_tenant uuid;
  v_errors jsonb;
begin
  select * into v_row from "better_supabase"."workflow_versions" x where x."id" = version for update;
  if not found then
    raise exception 'No such workflow version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = v_row."definition_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.publish'), false))) then
    raise exception 'You may not publish this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_row."status" = 'published' then
    return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
  end if;
  v_errors := "better_supabase"."validate_workflow_graph"(v_row."graph");
  if jsonb_array_length(v_errors) > 0 then
    raise exception '%', (select string_agg(value, '; ') from jsonb_array_elements_text(v_errors))
      using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "status" = 'archived'
  where x."definition_id" = v_row."definition_id" and x."status" = 'published';
  update "better_supabase"."workflow_versions" x set "status" = 'published', "compiled" = compiled, "published_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_workflow_node_run (
  run     text,
  node    text,
  status  text,
  attempt integer DEFAULT NULL::integer,
  output  jsonb   DEFAULT NULL::jsonb,
  error   text    DEFAULT NULL::text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_run uuid;
  v_ended boolean := status in ('completed', 'failed', 'skipped');
begin
  select x."id" into v_run from "better_supabase"."workflow_runs" x
  where x."id"::text = run or x."external_id" = run
  order by x."id"::text = run desc
  limit 1;
  if not found then
    return false;
  end if;
  insert into "better_supabase"."workflow_node_runs" as x ("run_id", "node_id", "status", "attempts", "output", "error", "started_at", "ended_at")
  values (v_run, node, status, coalesce(attempt, 0), output, left(error, 4000), now(), case when v_ended then now() end)
  on conflict ("run_id", "node_id") do update set
    "status" = excluded."status",
    "attempts" = greatest(x."attempts", excluded."attempts"),
    "output" = coalesce(excluded."output", x."output"),
    "error" = excluded."error",
    "started_at" = coalesce(x."started_at", excluded."started_at"),
    "ended_at" = excluded."ended_at";
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', v_run, 'node', node, 'status', status), 'node', 'workflow-run:' || v_run::text, true);
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_alert (
  alert uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  delete from "better_supabase"."workflow_alerts" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = alert and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_credential (
  credential uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_credentials"%rowtype;
begin
  delete from "better_supabase"."workflow_credentials" x
  where x."id" = credential and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)))
  returning * into v_row;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'kind', v_row."kind",
    'name', v_row."name",
    'ref', v_row."credential_ref",
    'scopes', to_jsonb(v_row."scopes"),
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  delete from "better_supabase"."workflow_definitions" x
  where x."id" = definition and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_trigger (
  trigger uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  delete from "better_supabase"."workflow_triggers" x
  using "better_supabase"."workflow_definitions" y
  where x."id" = trigger and y."id" = x."definition_id"
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (y."tenant_id" is not null and coalesce(better_supabase.can('tenant', y."tenant_id", 'workflow.edit'), false)));
  return found;
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
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run'
    ]
    else array[]::text[]
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rotate_workflow_webhook_token (
  trigger uuid
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_kind text;
  v_token text := 'wfh_' || encode(extensions.gen_random_bytes(24), 'hex');
begin
  select y."tenant_id", x."kind" into v_tenant, v_kind
  from "better_supabase"."workflow_triggers" x join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."id" = trigger;
  if not found then
    raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_kind <> 'webhook' then
    raise exception 'Only webhook triggers have tokens' using errcode = '22023', hint = 'WORKFLOW_TRIGGER_KIND';
  end if;
  delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
  insert into "better_supabase"."workflow_webhook_tokens" ("token_hash", "trigger_id")
  values (extensions.digest(v_token, 'sha256'), trigger);
  return v_token;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_alert (
  definition uuid,
  on_event   text,
  channel    jsonb    DEFAULT '{}'::jsonb,
  threshold  interval DEFAULT NULL::interval,
  alert      uuid     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_alerts"%rowtype;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage alerts for this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if alert is null then
    insert into "better_supabase"."workflow_alerts" ("definition_id", "on_event", "threshold", "channel", "created_by")
    values (definition, on_event, threshold, coalesce(channel, '{}'::jsonb), (select auth.uid()))
    returning * into v_row;
  else
    update "better_supabase"."workflow_alerts" x set "on_event" = on_event, "threshold" = threshold, "channel" = coalesce(channel, '{}'::jsonb)
    where x."id" = alert and x."definition_id" = definition
    returning * into v_row;
    if not found then
      raise exception 'No such alert' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'onEvent', v_row."on_event",
    'threshold', extract(epoch from v_row."threshold"),
    'channel', v_row."channel",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_credential (
  tenant uuid,
  kind   text,
  name   text,
  ref    jsonb,
  scopes text[] DEFAULT '{}'::text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_credentials"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not manage workflow credentials here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  insert into "better_supabase"."workflow_credentials" as x ("tenant_id", "kind", "name", "credential_ref", "scopes", "created_by")
  values (tenant, kind, name, ref, coalesce(scopes, '{}'), (select auth.uid()))
  on conflict on constraint workflow_credentials_tenant_name_key do update set
    "kind" = excluded."kind",
    "credential_ref" = excluded."credential_ref",
    "scopes" = excluded."scopes"
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'kind', v_row."kind",
    'name', v_row."name",
    'ref', v_row."credential_ref",
    'scopes', to_jsonb(v_row."scopes"),
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_definition (
  tenant      uuid,
  slug        text,
  name        text,
  description text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_definitions"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  insert into "better_supabase"."workflow_definitions" as x ("tenant_id", "slug", "name", "description", "created_by")
  values (tenant, slug, name, description, (select auth.uid()))
  on conflict on constraint workflow_definitions_tenant_slug_key do update set
    "name" = excluded."name",
    "description" = excluded."description",
    "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'slug', v_row."slug",
    'name', v_row."name",
    'description', v_row."description",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_draft (
  definition uuid,
  graph      jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_versions"%rowtype;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition for update;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'A graph is an object' using errcode = '22023', hint = 'WORKFLOW_GRAPH_INVALID';
  end if;
  update "better_supabase"."workflow_versions" x set "graph" = graph, "compiled" = null
  where x."definition_id" = definition and x."status" = 'draft'
  returning * into v_row;
  if not found then
    insert into "better_supabase"."workflow_versions" ("definition_id", "version", "graph", "created_by")
    values (
      definition,
      coalesce((select max(y."version") from "better_supabase"."workflow_versions" y where y."definition_id" = definition), 0) + 1,
      graph,
      (select auth.uid())
    )
    returning * into v_row;
  end if;
  update "better_supabase"."workflow_definitions" x set "updated_at" = now() where x."id" = definition;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_workflow_trigger (
  definition uuid,
  kind       text,
  config     jsonb   DEFAULT '{}'::jsonb,
  enabled    boolean DEFAULT true,
  trigger    uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_tenant uuid;
  v_row "better_supabase"."workflow_triggers"%rowtype;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'workflow.edit'), false))) then
    raise exception 'You may not edit this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if trigger is null then
    insert into "better_supabase"."workflow_triggers" ("definition_id", "kind", "config", "enabled")
    values (definition, kind, coalesce(config, '{}'::jsonb), coalesce(enabled, true))
    returning * into v_row;
  else
    update "better_supabase"."workflow_triggers" x set
      "kind" = kind,
      "config" = coalesce(config, '{}'::jsonb),
      "enabled" = coalesce(enabled, true),
      "updated_at" = now()
    where x."id" = trigger and x."definition_id" = definition
    returning * into v_row;
    if not found then
      raise exception 'No such trigger' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
    end if;
    if kind <> 'webhook' then
      delete from "better_supabase"."workflow_webhook_tokens" x where x."trigger_id" = trigger;
    end if;
  end if;
  return jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'kind', v_row."kind",
    'config', v_row."config",
    'enabled', v_row."enabled",
    'createdAt', v_row."created_at",
    'updatedAt', v_row."updated_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_workflow_steps (
  steps jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  insert into "better_supabase"."workflow_step_library" ("name", "title", "description", "input_schema", "output_schema", "credential_kind")
  select e.key, coalesce(e.value ->> 'title', e.key), e.value ->> 'description',
    coalesce(e.value -> 'inputSchema', '{}'::jsonb), coalesce(e.value -> 'outputSchema', '{}'::jsonb), e.value ->> 'credentialKind'
  from jsonb_each(coalesce(steps, '{}'::jsonb)) e
  on conflict ("name") do update set
    "title" = excluded."title",
    "description" = excluded."description",
    "input_schema" = excluded."input_schema",
    "output_schema" = excluded."output_schema",
    "credential_kind" = excluded."credential_kind",
    "updated_at" = now();
  delete from "better_supabase"."workflow_step_library" x
  where not exists (
    select 1 from jsonb_each(coalesce(steps, '{}'::jsonb)) e where e.key = x."name"
  );
  select count(*) into v_count from "better_supabase"."workflow_step_library";
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.validate_workflow_graph (
  graph jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_errors text[] := '{}';
  v_nodes jsonb := coalesce(graph -> 'nodes', 'null'::jsonb);
  v_edges jsonb := coalesce(graph -> 'edges', '[]'::jsonb);
  v_node jsonb;
  v_edge jsonb;
  v_ids text[] := '{}';
  v_triggers integer := 0;
begin
  if jsonb_typeof(v_nodes) <> 'array' or jsonb_typeof(v_edges) <> 'array' then
    return jsonb_build_array('A graph has a nodes array and an edges array');
  end if;
  for v_node in select value from jsonb_array_elements(v_nodes) loop
    if coalesce(jsonb_typeof(v_node -> 'id'), '') <> 'string' or length(v_node ->> 'id') not between 1 and 100 then
      v_errors := array_append(v_errors, 'Every node has an id of 1 to 100 characters');
      continue;
    end if;
    if (v_node ->> 'id') = any (v_ids) then
      v_errors := array_append(v_errors, format('Node %s appears twice', v_node ->> 'id'));
    end if;
    v_ids := array_append(v_ids, v_node ->> 'id');
    if coalesce(v_node ->> 'kind', '') not in ('trigger', 'step', 'sleep', 'approval', 'condition') then
      v_errors := array_append(v_errors, format('Node %s has an unknown kind', v_node ->> 'id'));
    elsif v_node ->> 'kind' = 'trigger' then
      v_triggers := v_triggers + 1;
    elsif v_node ->> 'kind' = 'step' and not exists (
      select 1 from "better_supabase"."workflow_step_library" s where s."name" = v_node ->> 'step'
    ) then
      v_errors := array_append(v_errors, format('Node %s uses step %s, which is not in the step library', v_node ->> 'id', coalesce(v_node ->> 'step', 'null')));
    end if;
  end loop;
  if v_triggers <> 1 then
    v_errors := array_append(v_errors, 'A graph has exactly one trigger node');
  end if;
  for v_edge in select value from jsonb_array_elements(v_edges) loop
    if not coalesce((v_edge ->> 'source') = any (v_ids), false) or not coalesce((v_edge ->> 'target') = any (v_ids), false) then
      v_errors := array_append(v_errors, format('Edge %s joins a node that does not exist', coalesce(v_edge ->> 'id', '?')));
    end if;
  end loop;
  return to_jsonb(v_errors);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_alerts_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'onEvent', x."on_event",
    'threshold', extract(epoch from x."threshold"),
    'channel', x."channel",
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_alerts" x where x."definition_id" = workflow_alerts_list.definition;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_credential_get (
  credential uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'kind', x."kind",
    'name', x."name",
    'ref', x."credential_ref",
    'scopes', to_jsonb(x."scopes"),
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) from "better_supabase"."workflow_credentials" x where x."id" = workflow_credential_get.credential;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_credentials_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'kind', x."kind",
    'name', x."name",
    'ref', x."credential_ref",
    'scopes', to_jsonb(x."scopes"),
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_credentials" x
  where workflow_credentials_list.tenant is null or x."tenant_id" = workflow_credentials_list.tenant;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_definition_get (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) from "better_supabase"."workflow_definitions" x where x."id" = workflow_definition_get.definition;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_definitions_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(
    jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'slug', x."slug",
    'name', x."name",
    'description', x."description",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) || jsonb_build_object(
      'published', (select y."version" from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'published'),
      'draft', exists (select 1 from "better_supabase"."workflow_versions" y where y."definition_id" = x."id" and y."status" = 'draft')
    ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_definitions" x
  where workflow_definitions_list.tenant is null or x."tenant_id" = workflow_definitions_list.tenant;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_event_targets (
  type   text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('trigger', jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'kind', x."kind",
    'config', x."config",
    'enabled', x."enabled",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ), 'tenant', y."tenant_id") order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_triggers" x
  join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where x."kind" = 'event' and x."enabled"
    and x."config" ->> 'type' = workflow_event_targets.type
    and y."tenant_id" is not distinct from workflow_event_targets.tenant;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_node_runs_list (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'run', x."run_id",
    'node', x."node_id",
    'status', x."status",
    'attempts', x."attempts",
    'output', x."output",
    'error', x."error",
    'startedAt', x."started_at",
    'endedAt', x."ended_at"
  ) order by x."started_at" nulls last, x."node_id"), '[]'::jsonb)
  from "better_supabase"."workflow_node_runs" x
  join "better_supabase"."workflow_runs" y on y."id" = x."run_id"
  where y."id"::text = workflow_node_runs_list.run or y."external_id" = workflow_node_runs_list.run;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_alert()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."workflow_runs"%rowtype := new;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_fired integer := 0;
begin
  if new."status" <> 'failed' or (tg_op = 'UPDATE' and old."status" = 'failed') then
    return null;
  end if;
  for v_alert in
    select * from "better_supabase"."workflow_alerts" x
    where x."on_event" = 'failed' and x."definition_id"::text = new."attributes" ->> 'bs.definition'
  loop
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
      end if;
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_start_target (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_def "better_supabase"."workflow_definitions"%rowtype;
  v_row "better_supabase"."workflow_versions"%rowtype;
begin
  select * into v_def from "better_supabase"."workflow_definitions" x where x."id" = definition;
  if not found then
    raise exception 'No such workflow' using errcode = 'P0002', hint = 'WORKFLOW_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_def."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_def."tenant_id", 'workflow.run'), false))) then
    raise exception 'You may not run this workflow' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."workflow_versions" x where x."definition_id" = definition and x."status" = 'published';
  if not found then
    raise exception 'This workflow has no published version' using errcode = 'P0002', hint = 'WORKFLOW_NOT_PUBLISHED';
  end if;
  return jsonb_build_object('definition', jsonb_build_object(
    'id', v_def."id",
    'tenant', v_def."tenant_id",
    'slug', v_def."slug",
    'name', v_def."name",
    'description', v_def."description",
    'createdBy', v_def."created_by",
    'createdAt', v_def."created_at",
    'updatedAt', v_def."updated_at"
  ), 'version', jsonb_build_object(
    'id', v_row."id",
    'definition', v_row."definition_id",
    'version', v_row."version",
    'status', v_row."status",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at",
    'publishedAt', v_row."published_at",
    'graph', v_row."graph",
    'compiled', v_row."compiled"
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_steps_list()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', x."name",
    'title', x."title",
    'description', x."description",
    'inputSchema', x."input_schema",
    'outputSchema', x."output_schema",
    'credentialKind', x."credential_kind",
    'updatedAt', x."updated_at"
  ) order by x."name"), '[]'::jsonb) from "better_supabase"."workflow_step_library" x;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_triggers_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'kind', x."kind",
    'config', x."config",
    'enabled', x."enabled",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ) order by x."created_at"), '[]'::jsonb)
  from "better_supabase"."workflow_triggers" x where x."definition_id" = workflow_triggers_list.definition;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_version_get (
  version uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'version', x."version",
    'status', x."status",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'publishedAt', x."published_at",
    'graph', x."graph",
    'compiled', x."compiled"
  ) from "better_supabase"."workflow_versions" x where x."id" = workflow_version_get.version;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_versions_list (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'version', x."version",
    'status', x."status",
    'createdBy', x."created_by",
    'createdAt', x."created_at",
    'publishedAt', x."published_at"
  ) order by x."version" desc), '[]'::jsonb)
  from "better_supabase"."workflow_versions" x where x."definition_id" = workflow_versions_list.definition;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_webhook_target (
  token text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object('trigger', jsonb_build_object(
    'id', x."id",
    'definition', x."definition_id",
    'kind', x."kind",
    'config', x."config",
    'enabled', x."enabled",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at"
  ), 'tenant', y."tenant_id")
  from "better_supabase"."workflow_webhook_tokens" k
  join "better_supabase"."workflow_triggers" x on x."id" = k."trigger_id"
  join "better_supabase"."workflow_definitions" y on y."id" = x."definition_id"
  where k."token_hash" = extensions.digest(workflow_webhook_target.token, 'sha256')
    and x."enabled";
$function$;

ALTER TABLE "better_supabase"."workflow_alert_fires"
  ADD CONSTRAINT "workflow_alert_fires_run_id_fkey" FOREIGN KEY (run_id) REFERENCES better_supabase.workflow_runs(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_alerts"
  ADD CONSTRAINT "workflow_alerts_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_alert_fires"
  ADD CONSTRAINT "workflow_alert_fires_alert_id_fkey" FOREIGN KEY (alert_id) REFERENCES better_supabase.workflow_alerts(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_credentials"
  ADD CONSTRAINT "workflow_credentials_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_definitions"
  ADD CONSTRAINT "workflow_definitions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_alerts"
  ADD CONSTRAINT "workflow_alerts_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES better_supabase.workflow_definitions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_node_runs"
  ADD CONSTRAINT "workflow_node_runs_run_id_fkey" FOREIGN KEY (run_id) REFERENCES better_supabase.workflow_runs(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_triggers"
  ADD CONSTRAINT "workflow_triggers_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES better_supabase.workflow_definitions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_versions"
  ADD CONSTRAINT "workflow_versions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_versions"
  ADD CONSTRAINT "workflow_versions_definition_id_fkey" FOREIGN KEY (definition_id) REFERENCES better_supabase.workflow_definitions(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."workflow_webhook_tokens"
  ADD CONSTRAINT "workflow_webhook_tokens_trigger_id_fkey" FOREIGN KEY (trigger_id) REFERENCES better_supabase.workflow_triggers(id) ON DELETE CASCADE;

CREATE INDEX workflow_alert_fires_run_idx ON better_supabase.workflow_alert_fires USING btree (run_id);

CREATE INDEX workflow_alerts_created_by_idx ON better_supabase.workflow_alerts USING btree (created_by);

CREATE INDEX workflow_alerts_definition_idx ON better_supabase.workflow_alerts USING btree (definition_id);

CREATE INDEX workflow_credentials_created_by_idx ON better_supabase.workflow_credentials USING btree (created_by);

CREATE INDEX workflow_definitions_created_by_idx ON better_supabase.workflow_definitions USING btree (created_by);

CREATE INDEX workflow_triggers_definition_idx ON better_supabase.workflow_triggers USING btree (definition_id);

CREATE INDEX workflow_versions_created_by_idx ON better_supabase.workflow_versions USING btree (created_by);

CREATE UNIQUE INDEX workflow_versions_one_draft_idx ON better_supabase.workflow_versions USING btree (definition_id)
  WHERE (status = 'draft'::text);

CREATE UNIQUE INDEX workflow_versions_one_published_idx ON better_supabase.workflow_versions USING btree (definition_id)
  WHERE (status = 'published'::text);

CREATE TRIGGER bs_workflow_runs_alert
  AFTER INSERT OR UPDATE OF status ON better_supabase.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_runs_alert();

CREATE POLICY "workflow_alerts_read" ON "better_supabase"."workflow_alerts"
  FOR SELECT
  TO "authenticated"
  USING ((definition_id IN ( SELECT x.id
   FROM better_supabase.workflow_definitions x)));

CREATE POLICY "workflow_credentials_read" ON "better_supabase"."workflow_credentials"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)));

CREATE POLICY "workflow_definitions_read" ON "better_supabase"."workflow_definitions"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)));

CREATE POLICY "workflow_node_runs_read" ON "better_supabase"."workflow_node_runs"
  FOR SELECT
  TO "authenticated"
  USING ((run_id IN ( SELECT x.id
   FROM better_supabase.workflow_runs x)));

CREATE POLICY "workflow_step_library_read" ON "better_supabase"."workflow_step_library"
  FOR SELECT
  TO "authenticated"
  USING (true);

CREATE POLICY "workflow_triggers_read" ON "better_supabase"."workflow_triggers"
  FOR SELECT
  TO "authenticated"
  USING ((definition_id IN ( SELECT x.id
   FROM better_supabase.workflow_definitions x)));

CREATE POLICY "workflow_versions_read" ON "better_supabase"."workflow_versions"
  FOR SELECT
  TO "authenticated"
  USING ((definition_id IN ( SELECT x.id
   FROM better_supabase.workflow_definitions x)));

REVOKE ALL ON FUNCTION "api"."check_workflow_alerts"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."check_workflow_alerts"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."publish_workflow_version"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."publish_workflow_version"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_workflow_node_run"(text, text, text, integer, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_workflow_node_run"(text, text, text, integer, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."remove_workflow_alert"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_workflow_alert"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_workflow_credential"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_workflow_credential"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_workflow_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_workflow_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."remove_workflow_trigger"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_workflow_trigger"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."rotate_workflow_webhook_token"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."rotate_workflow_webhook_token"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_workflow_credential"(uuid, text, text, jsonb, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_workflow_credential"(uuid, text, text, jsonb, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_workflow_definition"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_workflow_definition"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_workflow_draft"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_workflow_draft"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."sync_workflow_steps"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."sync_workflow_steps"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."validate_workflow_graph"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."validate_workflow_graph"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_alerts_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_alerts_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_credential_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_credential_get"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_credentials_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_credentials_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_definition_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_definition_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_definitions_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_definitions_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_event_targets"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_event_targets"(text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_node_runs_list"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_node_runs_list"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_start_target"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_start_target"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_steps_list"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_steps_list"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_triggers_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_triggers_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_version_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_version_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_versions_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_versions_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_webhook_target"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_webhook_target"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."check_workflow_alerts"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."check_workflow_alerts"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."publish_workflow_version"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."publish_workflow_version"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_workflow_node_run"(text, text, text, integer, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_workflow_node_run"(text, text, text, integer, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_workflow_alert"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_workflow_alert"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_workflow_credential"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_workflow_credential"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_workflow_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_workflow_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_workflow_trigger"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_workflow_trigger"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."rotate_workflow_webhook_token"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."rotate_workflow_webhook_token"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_workflow_alert"(uuid, text, jsonb, interval, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_workflow_credential"(uuid, text, text, jsonb, text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_workflow_credential"(uuid, text, text, jsonb, text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_workflow_definition"(uuid, text, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_workflow_definition"(uuid, text, text, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_workflow_draft"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_workflow_draft"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."save_workflow_trigger"(uuid, text, jsonb, boolean, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sync_workflow_steps"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sync_workflow_steps"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."validate_workflow_graph"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."validate_workflow_graph"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_alerts_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_alerts_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_credential_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_credential_get"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_credentials_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_credentials_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_definition_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_definition_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_definitions_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_definitions_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_event_targets"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_event_targets"(text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_node_runs_list"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_node_runs_list"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_runs_alert"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."workflow_start_target"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_start_target"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_steps_list"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_steps_list"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_triggers_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_triggers_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_version_get"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_version_get"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_versions_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_versions_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_webhook_target"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_webhook_target"(text) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_alert_fires" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_alerts" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_alerts" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_credentials" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_credentials" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_definitions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_definitions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_node_runs" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_node_runs" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_step_library" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_step_library" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_triggers" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_triggers" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_versions" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_versions" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_webhook_tokens" TO "service_role";
