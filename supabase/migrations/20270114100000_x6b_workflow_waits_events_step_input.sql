SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."workflow_triggers"
  DROP CONSTRAINT "bsb_workflow_triggers_kind_check";

DROP FUNCTION "api"."record_workflow_node_run"(text, text, text, integer, jsonb, text);

DROP FUNCTION "better_supabase"."record_workflow_node_run"(text, text, text, integer, jsonb, text);

ALTER TABLE "better_supabase"."workflow_node_runs"
  ADD COLUMN "input" jsonb;

CREATE OR REPLACE FUNCTION api.record_workflow_node_run (
  run     text,
  node    text,
  status  text,
  attempt integer DEFAULT NULL::integer,
  output  jsonb   DEFAULT NULL::jsonb,
  error   text    DEFAULT NULL::text,
  input   jsonb   DEFAULT NULL::jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_workflow_node_run"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.workflow_event_targets (
  event  text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_event_targets"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.record_workflow_node_run (
  run     text,
  node    text,
  status  text,
  attempt integer DEFAULT NULL::integer,
  output  jsonb   DEFAULT NULL::jsonb,
  error   text    DEFAULT NULL::text,
  input   jsonb   DEFAULT NULL::jsonb
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
  insert into "better_supabase"."workflow_node_runs" as x ("run_id", "node_id", "status", "attempts", "input", "output", "error", "started_at", "ended_at")
  values (v_run, node, status, coalesce(attempt, 0), input, output, left(error, 4000), now(), case when v_ended then now() end)
  on conflict ("run_id", "node_id") do update set
    "status" = excluded."status",
    "attempts" = greatest(x."attempts", excluded."attempts"),
    "input" = coalesce(excluded."input", x."input"),
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

CREATE OR REPLACE FUNCTION better_supabase.workflow_event_targets (
  event  text,
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
  where x."kind" = 'event'
    and x."enabled"
    and (
      x."config" ->> 'event' = workflow_event_targets.event
      or (
        x."config" ->> 'event' like '%.*'
        and workflow_event_targets.event like left(x."config" ->> 'event', -1) || '%'
      )
    )
    and (workflow_event_targets.tenant is null or y."tenant_id" is null or y."tenant_id" = workflow_event_targets.tenant);
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
    'input', x."input",
    'output', x."output",
    'error', x."error",
    'startedAt', x."started_at",
    'endedAt', x."ended_at"
  ) order by x."started_at" nulls last, x."node_id"), '[]'::jsonb)
  from "better_supabase"."workflow_node_runs" x
  join "better_supabase"."workflow_runs" y on y."id" = x."run_id"
  where y."id"::text = workflow_node_runs_list.run or y."external_id" = workflow_node_runs_list.run;
$function$;

ALTER TABLE "better_supabase"."workflow_triggers"
  ADD CONSTRAINT "bsb_workflow_triggers_kind_check" CHECK ((kind = ANY (ARRAY['manual'::text, 'webhook'::text, 'schedule'::text, 'form'::text, 'chat'::text, 'event'::text])));

REVOKE ALL ON FUNCTION "api"."record_workflow_node_run"(text, text, text, integer, jsonb, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_workflow_node_run"(text, text, text, integer, jsonb, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_event_targets"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_event_targets"(text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_workflow_node_run"(text, text, text, integer, jsonb, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_workflow_node_run"(text, text, text, integer, jsonb, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_event_targets"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_event_targets"(text, uuid) TO "service_role";
