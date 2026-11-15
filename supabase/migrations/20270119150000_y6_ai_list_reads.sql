SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_eval_datasets (
  tenant   uuid    DEFAULT NULL::uuid,
  after    text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_eval_datasets"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.list_guardrail_policies (
  tenant      uuid    DEFAULT NULL::uuid,
  agent       text    DEFAULT NULL::text,
  after_agent text    DEFAULT NULL::text,
  after_stage text    DEFAULT NULL::text,
  max_rows    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_guardrail_policies"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.list_prompts (
  tenant   uuid    DEFAULT NULL::uuid,
  after    text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_prompts"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_eval_datasets (
  tenant   uuid    DEFAULT NULL::uuid,
  after    text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_eval_datasets.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.name), '[]'::jsonb) into v_items
  from (
    select x."name" as name, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'description', x."description", 'created_at', x."created_at") || jsonb_build_object(
      'item_count', (select count(*) from "better_supabase"."eval_items" i where i."dataset_id" = x."id"),
      'run_count', (select count(*) from "better_supabase"."eval_runs" r where r."dataset_id" = x."id"),
      'last_run_at', (select max(r."created_at") from "better_supabase"."eval_runs" r where r."dataset_id" = x."id")
    ) as item
    from "better_supabase"."eval_datasets" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_eval_datasets.tenant::text, '')
      and (list_eval_datasets.after is null or x."name" > list_eval_datasets.after)
    order by x."name"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'name') else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_guardrail_policies (
  tenant      uuid    DEFAULT NULL::uuid,
  agent       text    DEFAULT NULL::text,
  after_agent text    DEFAULT NULL::text,
  after_stage text    DEFAULT NULL::text,
  max_rows    integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_guardrail_policies.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.agent, n.stage), '[]'::jsonb) into v_items
  from (
    select x."agent" as agent, x."stage" as stage, jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'agent', x."agent", 'stage', x."stage", 'config', x."config", 'enabled', x."enabled", 'updated_at', x."updated_at") as item
    from "better_supabase"."guardrail_policies" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_guardrail_policies.tenant::text, '')
      and (list_guardrail_policies.agent is null or x."agent" = list_guardrail_policies.agent)
      and (list_guardrail_policies.after_agent is null or (x."agent", x."stage") > (list_guardrail_policies.after_agent, coalesce(list_guardrail_policies.after_stage, '')))
    order by x."agent", x."stage"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'agent', v_items -> (v_size - 1) ->> 'stage') else null end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_prompts (
  tenant   uuid    DEFAULT NULL::uuid,
  after    text    DEFAULT NULL::text,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_size integer := least(greatest(coalesce(list_prompts.max_rows, 50), 1), 200);
  v_items jsonb;
  v_more boolean;
begin
  select coalesce(jsonb_agg(n.item order by n.name), '[]'::jsonb) into v_items
  from (
    select x."name" as name, jsonb_build_object(
      'name', x."name",
      'tenant_id', list_prompts.tenant,
      'latest_version', max(x."version"),
      'version_count', count(*),
      'updated_at', max(x."created_at"),
      'labels', coalesce((
        select jsonb_object_agg(y."label", y."version") from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(list_prompts.tenant::text, '') and y."name" = x."name"
      ), '{}'::jsonb)
    ) as item
    from "better_supabase"."prompt_versions" x
    where coalesce(x."tenant_id"::text, '') = coalesce(list_prompts.tenant::text, '')
      and (list_prompts.after is null or x."name" > list_prompts.after)
    group by x."name"
    order by x."name"
    limit v_size + 1
  ) n;
  v_more := jsonb_array_length(v_items) > v_size;
  if v_more then
    v_items := v_items - v_size;
  end if;
  return jsonb_build_object(
    'items', v_items,
    'hasMore', v_more,
    'nextCursor', case when v_more then jsonb_build_array(v_items -> (v_size - 1) ->> 'name') else null end
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_eval_datasets"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_eval_datasets"(uuid, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_guardrail_policies"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_guardrail_policies"(uuid, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_prompts"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_prompts"(uuid, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_eval_datasets"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_eval_datasets"(uuid, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_guardrail_policies"(uuid, text, text, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_prompts"(uuid, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_prompts"(uuid, text, integer) TO "service_role";
