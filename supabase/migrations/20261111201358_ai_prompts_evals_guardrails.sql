SET local check_function_bodies = off;

CREATE TABLE "better_supabase"."eval_datasets" (
  "id"          uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"   uuid,
  "name"        text                     NOT NULL,
  "description" text,
  "created_at"  timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_eval_datasets_description_check" CHECK ((length(description) <= 2000)),
  CONSTRAINT "bsb_eval_datasets_name_check" CHECK ((name ~ '^[a-z0-9][a-z0-9_.:/-]{0,127}$'::text)),
  CONSTRAINT "eval_datasets_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."eval_datasets"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."eval_items" (
  "id"                uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "dataset_id"        uuid                     NOT NULL,
  "input"             jsonb                    NOT NULL,
  "expected"          jsonb,
  "metadata"          jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "source_chat_id"    text,
  "source_message_id" text,
  "created_at"        timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_eval_items_metadata_check" CHECK ((jsonb_typeof(metadata) = 'object'::text)),
  CONSTRAINT "eval_items_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."eval_items"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."eval_results" (
  "run_id"     uuid                     NOT NULL,
  "item_id"    uuid                     NOT NULL,
  "output"     text,
  "scores"     jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "passed"     boolean                  NOT NULL,
  "error"      text,
  "latency_ms" integer,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_eval_results_latency_ms_check" CHECK ((latency_ms >= 0)),
  CONSTRAINT "bsb_eval_results_scores_check" CHECK ((jsonb_typeof(scores) = 'object'::text)),
  CONSTRAINT "eval_results_pkey" PRIMARY KEY (run_id, item_id)
);

ALTER TABLE "better_supabase"."eval_results"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."eval_runs" (
  "id"             uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "dataset_id"     uuid                     NOT NULL,
  "tenant_id"      uuid,
  "prompt_name"    text                     NOT NULL,
  "prompt_version" integer                  NOT NULL,
  "model"          text                     NOT NULL,
  "scorers"        jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "status"         text                     NOT NULL DEFAULT 'running'::text,
  "summary"        jsonb,
  "created_at"     timestamp with time zone NOT NULL DEFAULT now(),
  "finished_at"    timestamp with time zone,
  CONSTRAINT "bsb_eval_runs_prompt_version_check" CHECK ((prompt_version >= 1)),
  CONSTRAINT "bsb_eval_runs_scorers_check" CHECK ((jsonb_typeof(scorers) = 'array'::text)),
  CONSTRAINT "bsb_eval_runs_status_check" CHECK ((status = ANY (ARRAY['running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text]))),
  CONSTRAINT "eval_runs_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."eval_runs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."guardrail_decisions" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid,
  "agent"        text                     NOT NULL,
  "stage"        text                     NOT NULL,
  "decision"     text                     NOT NULL,
  "reasons"      jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "chat_id"      text,
  "content_hash" text,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_guardrail_decisions_decision_check" CHECK ((decision = ANY (ARRAY['allow'::text, 'redact'::text, 'block'::text]))),
  CONSTRAINT "bsb_guardrail_decisions_reasons_check" CHECK ((jsonb_typeof(reasons) = 'array'::text)),
  CONSTRAINT "bsb_guardrail_decisions_stage_check" CHECK ((stage = ANY (ARRAY['input'::text, 'output'::text]))),
  CONSTRAINT "guardrail_decisions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."guardrail_decisions"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."guardrail_policies" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid,
  "agent"      text                     NOT NULL,
  "stage"      text                     NOT NULL,
  "config"     jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "enabled"    boolean                  NOT NULL DEFAULT true,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_guardrail_policies_agent_check" CHECK ((agent ~ '^(\*|[a-z0-9][a-z0-9_.:/-]{0,127})$'::text)),
  CONSTRAINT "bsb_guardrail_policies_config_check" CHECK ((jsonb_typeof(config) = 'object'::text)),
  CONSTRAINT "bsb_guardrail_policies_stage_check" CHECK ((stage = ANY (ARRAY['input'::text, 'output'::text]))),
  CONSTRAINT "guardrail_policies_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."guardrail_policies"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."prompt_labels" (
  "tenant_id"  uuid,
  "name"       text                     NOT NULL,
  "label"      text                     NOT NULL,
  "version"    integer                  NOT NULL,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_prompt_labels_label_check" CHECK ((label ~ '^[a-z0-9][a-z0-9_-]{0,63}$'::text)),
  CONSTRAINT "bsb_prompt_labels_version_check" CHECK ((version >= 1))
);

ALTER TABLE "better_supabase"."prompt_labels"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."prompt_versions" (
  "id"         uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"  uuid,
  "name"       text                     NOT NULL,
  "version"    integer                  NOT NULL,
  "template"   text                     NOT NULL,
  "variables"  jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "bsb_prompt_versions_name_check" CHECK ((name ~ '^[a-z0-9][a-z0-9_.:/-]{0,127}$'::text)),
  CONSTRAINT "bsb_prompt_versions_template_check" CHECK (((length(template) >= 1) AND (length(template) <= 102400))),
  CONSTRAINT "bsb_prompt_versions_variables_check" CHECK ((jsonb_typeof(variables) = 'array'::text)),
  CONSTRAINT "bsb_prompt_versions_version_check" CHECK ((version >= 1)),
  CONSTRAINT "prompt_versions_pkey" PRIMARY KEY (id)
);

ALTER TABLE "better_supabase"."prompt_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.add_eval_items (
  dataset uuid,
  items   jsonb
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_eval_items"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.add_eval_items_from_feedback (
  dataset  uuid,
  rating   integer                  DEFAULT '-1'::integer,
  since    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows integer                  DEFAULT 100
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."add_eval_items_from_feedback"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.compare_eval_runs (
  base       uuid,
  candidate  uuid,
  score_drop numeric DEFAULT NULL::numeric
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."compare_eval_runs"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.create_eval_dataset (
  name        text,
  tenant      uuid DEFAULT NULL::uuid,
  description text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_eval_dataset"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.create_eval_run (
  dataset        uuid,
  prompt_name    text,
  prompt_version integer,
  model          text,
  scorers        jsonb   DEFAULT '[]'::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_eval_run"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.create_prompt_version (
  name      text,
  template  text,
  tenant    uuid  DEFAULT NULL::uuid,
  variables jsonb DEFAULT '[]'::jsonb,
  label     text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_prompt_version"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.eval_run_summary (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."eval_run_summary"($1) $function$;

CREATE OR REPLACE FUNCTION api.finish_eval_run (
  run    uuid,
  status text DEFAULT 'completed'::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."finish_eval_run"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.get_eval_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_eval_run"($1) $function$;

CREATE OR REPLACE FUNCTION api.get_guardrail_policy (
  agent  text,
  stage  text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_guardrail_policy"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.get_prompt (
  name    text,
  label   text    DEFAULT 'production'::text,
  version integer DEFAULT NULL::integer,
  tenant  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_prompt"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_eval_items (
  dataset     uuid,
  pending_run uuid    DEFAULT NULL::uuid,
  after       uuid    DEFAULT NULL::uuid,
  max_rows    integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_eval_items"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_eval_results (
  run         uuid,
  only_failed boolean DEFAULT false,
  after       uuid    DEFAULT NULL::uuid,
  max_rows    integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_eval_results"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_eval_runs (
  dataset  uuid,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_eval_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.list_guardrail_decisions (
  agent    text    DEFAULT NULL::text,
  decision text    DEFAULT NULL::text,
  tenant   uuid    DEFAULT NULL::uuid,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_guardrail_decisions"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.list_prompt_versions (
  name   text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_prompt_versions"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_guardrail_decisions()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_guardrail_decisions"() $function$;

CREATE OR REPLACE FUNCTION api.record_eval_result (
  run        uuid,
  item       uuid,
  output     text    DEFAULT NULL::text,
  scores     jsonb   DEFAULT '{}'::jsonb,
  error      text    DEFAULT NULL::text,
  latency_ms integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_eval_result"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION api.record_guardrail_decision (
  agent        text,
  stage        text,
  decision     text,
  reasons      jsonb DEFAULT '[]'::jsonb,
  tenant       uuid  DEFAULT NULL::uuid,
  chat         text  DEFAULT NULL::text,
  content_hash text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_guardrail_decision"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.set_guardrail_policy (
  agent   text,
  stage   text,
  config  jsonb,
  tenant  uuid    DEFAULT NULL::uuid,
  enabled boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_guardrail_policy"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.set_prompt_label (
  name    text,
  label   text,
  version integer,
  tenant  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_prompt_label"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.add_eval_items (
  dataset uuid,
  items   jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_count integer;
begin
  if not exists (select 1 from "better_supabase"."eval_datasets" x where x."id" = add_eval_items.dataset) then
    raise exception 'No eval dataset %', add_eval_items.dataset using errcode = 'P0002', hint = 'EVAL_DATASET_NOT_FOUND';
  end if;
  if jsonb_typeof(add_eval_items.items) is distinct from 'array' then
    raise exception 'items must be a JSON array' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(add_eval_items.items) e where jsonb_typeof(e.value) <> 'object' or not (e.value ? 'input')) then
    raise exception 'every item needs an input' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  if (select count(*) from "better_supabase"."eval_items" x where x."dataset_id" = add_eval_items.dataset) + jsonb_array_length(add_eval_items.items) > 5000 then
    raise exception 'A dataset holds at most 5000 items' using errcode = '54000', hint = 'EVAL_DATASET_FULL';
  end if;
  insert into "better_supabase"."eval_items" ("dataset_id", "input", "expected", "metadata")
  select add_eval_items.dataset, e.value -> 'input', e.value -> 'expected', coalesce(e.value -> 'metadata', '{}'::jsonb)
  from jsonb_array_elements(add_eval_items.items) e;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.add_eval_items_from_feedback (
  dataset  uuid,
  rating   integer                  DEFAULT '-1'::integer,
  since    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_rows integer                  DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_dataset "better_supabase"."eval_datasets"%rowtype;
  v_count integer;
begin
  select x.* into v_dataset from "better_supabase"."eval_datasets" x where x."id" = add_eval_items_from_feedback.dataset;
  if not found then
    raise exception 'No eval dataset %', add_eval_items_from_feedback.dataset using errcode = 'P0002', hint = 'EVAL_DATASET_NOT_FOUND';
  end if;
  if add_eval_items_from_feedback.rating not in (-1, 1) then
    raise exception 'rating must be 1 or -1' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  with picked as materialized (
    select fb."chat_id" as chat_id, fb."message_id"::text as message_id,
      (select string_agg(p.value ->> 'text', '' order by p.ordinality) from jsonb_array_elements(case when jsonb_typeof(q.parts) = 'array' then q.parts else '[]'::jsonb end) with ordinality as p(value, ordinality) where p.value ->> 'type' = 'text') as prompt,
      (select string_agg(p.value ->> 'text', '' order by p.ordinality) from jsonb_array_elements(case when jsonb_typeof(a.parts) = 'array' then a.parts else '[]'::jsonb end) with ordinality as p(value, ordinality) where p.value ->> 'type' = 'text') as reply,
      fb."reason" as reason,
      fb."comment" as comment
    from "better_supabase"."ai_message_feedback" fb
    join "better_supabase"."ai_messages" a on a."chat_id" = fb."chat_id" and a."id" = fb."message_id"
    join "better_supabase"."ai_messages" q on q."chat_id" = a."chat_id" and q."id" = a."parent_id"
    join "better_supabase"."ai_chats" ch on ch."id" = fb."chat_id"
    where fb."rating" = add_eval_items_from_feedback.rating
      and (v_dataset."tenant_id" is null or ch."tenant_id" = v_dataset."tenant_id")
      and (add_eval_items_from_feedback.since is null or fb."updated_at" >= add_eval_items_from_feedback.since)
    order by fb."updated_at" desc
    limit least(greatest(coalesce(add_eval_items_from_feedback.max_rows, 100), 1), 1000)
  ), added as (
    insert into "better_supabase"."eval_items" ("dataset_id", "input", "expected", "metadata", "source_chat_id", "source_message_id")
    select v_dataset."id", jsonb_build_object('prompt', p.prompt),
      case when add_eval_items_from_feedback.rating = 1 then jsonb_build_object('output', p.reply) end,
      jsonb_build_object('source', 'ai-chat-feedback', 'rating', add_eval_items_from_feedback.rating, 'reason', p.reason, 'comment', p.comment, 'reply', p.reply),
      p.chat_id::text, p.message_id
    from picked p
    where p.prompt is not null
    on conflict do nothing
    returning 1
  )
  select count(*) into v_count from added;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.compare_eval_runs (
  base       uuid,
  candidate  uuid,
  score_drop numeric DEFAULT NULL::numeric
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_base "better_supabase"."eval_runs"%rowtype;
  v_candidate "better_supabase"."eval_runs"%rowtype;
  v_base_summary jsonb;
  v_candidate_summary jsonb;
begin
  select x.* into v_base from "better_supabase"."eval_runs" x where x."id" = compare_eval_runs.base;
  if not found then
    raise exception 'No eval run %', compare_eval_runs.base using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
  end if;
  select x.* into v_candidate from "better_supabase"."eval_runs" x where x."id" = compare_eval_runs.candidate;
  if not found then
    raise exception 'No eval run %', compare_eval_runs.candidate using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
  end if;
  if v_base."dataset_id" <> v_candidate."dataset_id" then
    raise exception 'Runs belong to different datasets' using errcode = '22023', hint = 'EVAL_RUN_MISMATCH';
  end if;
  v_base_summary := "better_supabase"."eval_run_summary"(compare_eval_runs.base);
  v_candidate_summary := "better_supabase"."eval_run_summary"(compare_eval_runs.candidate);
  return (
    with joined as materialized (
      select coalesce(b."item_id", c."item_id") as item,
        b."passed" as base_passed, c."passed" as candidate_passed,
        (select avg((e.value ->> 'score')::numeric) from jsonb_each(b."scores") e) as base_score, (select avg((e.value ->> 'score')::numeric) from jsonb_each(c."scores") e) as candidate_score,
        b."output" as base_output, c."output" as candidate_output
      from (select * from "better_supabase"."eval_results" where "run_id" = compare_eval_runs.base) b
      full join (select * from "better_supabase"."eval_results" where "run_id" = compare_eval_runs.candidate) c on c."item_id" = b."item_id"
    ), tagged as (
      select j.*, case
        when j.base_passed is null or j.candidate_passed is null then 'missing'
        when j.base_passed and not j.candidate_passed then 'regression'
        when not j.base_passed and j.candidate_passed then 'improvement'
        when compare_eval_runs.score_drop is not null and j.base_score - j.candidate_score > compare_eval_runs.score_drop then 'regression'
        when compare_eval_runs.score_drop is not null and j.candidate_score - j.base_score > compare_eval_runs.score_drop then 'improvement'
        else 'unchanged' end as kind
      from joined j
    )
    select jsonb_build_object(
      'base', v_base_summary,
      'candidate', v_candidate_summary,
      'pass_rate_delta', round(coalesce((v_candidate_summary ->> 'passRate')::numeric, 0) - coalesce((v_base_summary ->> 'passRate')::numeric, 0), 4),
      'regressions', coalesce(jsonb_agg(jsonb_build_object('item_id', t.item, 'base_score', t.base_score, 'candidate_score', t.candidate_score, 'base_output', t.base_output, 'candidate_output', t.candidate_output) order by t.item) filter (where t.kind = 'regression'), '[]'::jsonb),
      'improvements', coalesce(jsonb_agg(jsonb_build_object('item_id', t.item, 'base_score', t.base_score, 'candidate_score', t.candidate_score) order by t.item) filter (where t.kind = 'improvement'), '[]'::jsonb),
      'unchanged', count(*) filter (where t.kind = 'unchanged'),
      'missing', count(*) filter (where t.kind = 'missing')
    )
    from tagged t
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_eval_dataset (
  name        text,
  tenant      uuid DEFAULT NULL::uuid,
  description text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_datasets"%rowtype;
begin
  insert into "better_supabase"."eval_datasets" ("tenant_id", "name", "description")
  values (create_eval_dataset.tenant, create_eval_dataset.name, create_eval_dataset.description)
  on conflict ((coalesce("tenant_id"::text, '')), "name") do update set
    "description" = coalesce(excluded."description", "better_supabase"."eval_datasets"."description")
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_eval_run (
  dataset        uuid,
  prompt_name    text,
  prompt_version integer,
  model          text,
  scorers        jsonb   DEFAULT '[]'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_dataset "better_supabase"."eval_datasets"%rowtype;
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  select x.* into v_dataset from "better_supabase"."eval_datasets" x where x."id" = create_eval_run.dataset;
  if not found then
    raise exception 'No eval dataset %', create_eval_run.dataset using errcode = 'P0002', hint = 'EVAL_DATASET_NOT_FOUND';
  end if;
  insert into "better_supabase"."eval_runs" ("dataset_id", "tenant_id", "prompt_name", "prompt_version", "model", "scorers")
  values (create_eval_run.dataset, v_dataset."tenant_id", create_eval_run.prompt_name, create_eval_run.prompt_version, create_eval_run.model, coalesce(create_eval_run.scorers, '[]'::jsonb))
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'tenant_id', v_row."tenant_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_prompt_version (
  name      text,
  template  text,
  tenant    uuid  DEFAULT NULL::uuid,
  variables jsonb DEFAULT '[]'::jsonb,
  label     text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
  v_next integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(coalesce(create_prompt_version.tenant::text, '') || ':' || create_prompt_version.name, 0));
  select coalesce(max(x."version"), 0) + 1 into v_next from "better_supabase"."prompt_versions" x
  where coalesce(x."tenant_id"::text, '') = coalesce(create_prompt_version.tenant::text, '') and x."name" = create_prompt_version.name;
  insert into "better_supabase"."prompt_versions" ("tenant_id", "name", "version", "template", "variables")
  values (create_prompt_version.tenant, create_prompt_version.name, v_next, create_prompt_version.template, coalesce(create_prompt_version.variables, '[]'::jsonb))
  returning * into v_row;
  if create_prompt_version.label is not null then
    insert into "better_supabase"."prompt_labels" ("tenant_id", "name", "label", "version")
    values (create_prompt_version.tenant, create_prompt_version.name, create_prompt_version.label, v_next)
    on conflict ((coalesce("tenant_id"::text, '')), "name", "label") do update set
      "version" = excluded."version",
      "updated_at" = now();
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
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
    ('user', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'user_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.ai_chat_links', '"better_supabase"."ai_chat_links"', 'created_by', true, array['salt']::text[], true),
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
    ('user', 'better_supabase.status_history', '"better_supabase"."status_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.share_links', '"better_supabase"."share_links"', 'created_by', true, array['token_hash', 'password_hash']::text[], true),
    ('user', 'better_supabase.reminders', '"better_supabase"."reminders"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.import_runs', '"better_supabase"."import_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.subject_members', '"better_supabase"."subject_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.saved_view_preferences', '"better_supabase"."saved_view_preferences"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bulk_runs', '"better_supabase"."bulk_runs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_events', '"better_supabase"."calendar_events"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_attendees', '"better_supabase"."calendar_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.calendar_working_hours', '"better_supabase"."calendar_working_hours"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.bookings', '"better_supabase"."bookings"', 'customer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.versions', '"better_supabase"."versions"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.trash_items', '"better_supabase"."trash_items"', 'trashed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.reactions', '"better_supabase"."reactions"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.custom_emoji', '"better_supabase"."custom_emoji"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_requests', '"better_supabase"."approval_requests"', 'requested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_decisions', '"better_supabase"."approval_decisions"', 'approver', true, '{}'::text[], true),
    ('user', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'decided_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.deals', '"better_supabase"."deals"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.deal_members', '"better_supabase"."deal_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.application_scorecards', '"better_supabase"."application_scorecards"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.work_items', '"better_supabase"."work_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_checklist_items', '"better_supabase"."work_item_checklist_items"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.work_item_assignees', '"better_supabase"."work_item_assignees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.pipeline_stage_history', '"better_supabase"."pipeline_stage_history"', 'actor_id', true, '{}'::text[], true),
    ('user', 'better_supabase.activities', '"better_supabase"."activities"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.quotes', '"better_supabase"."quotes"', 'owner_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employees', '"better_supabase"."employees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'reporter_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'notifier_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'appellant_id', true, '{}'::text[], true),
    ('user', 'better_supabase.assets', '"better_supabase"."assets"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_models', '"better_supabase"."score_models"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.score_model_versions', '"better_supabase"."score_model_versions"', 'saved_by', true, '{}'::text[], true),
    ('user', 'better_supabase.passes', '"better_supabase"."passes"', 'holder_id', true, '{}'::text[], true),
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
    ('user', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'submitted_by', true, '{}'::text[], true),
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
    ('user', 'better_supabase.shift_swaps', '"better_supabase"."shift_swaps"', 'from_id', true, '{}'::text[], true),
    ('user', 'better_supabase.shift_availability', '"better_supabase"."shift_availability"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.observations', '"better_supabase"."observations"', 'performer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.care_plan_evaluations', '"better_supabase"."care_plan_evaluations"', 'author_id', true, '{}'::text[], true),
    ('user', 'better_supabase.inspection_members', '"better_supabase"."inspection_members"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'user_id', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'read_by', true, '{}'::text[], true),
    ('user', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'performed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tested_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'appraisee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'reviewer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'calibrated_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'assignee_id', true, '{}'::text[], true),
    ('user', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'submitted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'opened_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'counted_by', true, '{}'::text[], true),
    ('user', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'created_by', true, '{}'::text[], true),
    ('user', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'decided_by', true, '{}'::text[], true),
    ('user', 'better_supabase.periods', '"better_supabase"."periods"', 'closed_by', true, '{}'::text[], true),
    ('user', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'satisfied_by', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commissions', '"better_supabase"."commissions"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'seller_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.referrals', '"better_supabase"."referrals"', 'referrer_id', true, '{}'::text[], true),
    ('user', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'prescriber_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.audit_events', '"better_supabase"."audit_events"', 'tenant_id', false, array['old_record', 'new_record', 'impersonated_by', 'impersonation_reason', 'support_session_id']::text[], true),
    ('organization', 'public.memberships', '"public"."memberships"', 'organization_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'tenant_id', true, array['token_hash']::text[], true),
    ('organization', 'better_supabase.permission_overrides', '"better_supabase"."permission_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.outbox_events', '"better_supabase"."outbox_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_events', '"better_supabase"."notification_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_recipients', '"better_supabase"."notification_recipients"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_deliveries', '"better_supabase"."notification_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_delivery_events', '"better_supabase"."notification_delivery_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_subscriptions', '"better_supabase"."notification_subscriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.notification_digests', '"better_supabase"."notification_digests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.webhook_endpoint_secrets', '"better_supabase"."webhook_endpoint_secrets"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.webhook_deliveries', '"better_supabase"."webhook_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.organization_settings', '"better_supabase"."organization_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_counters', '"better_supabase"."usage_counters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_events', '"better_supabase"."usage_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_distinct', '"better_supabase"."usage_distinct"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_billed_periods', '"better_supabase"."usage_billed_periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.usage_quotas', '"better_supabase"."usage_quotas"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.flag_overrides', '"better_supabase"."flag_overrides"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_nodes', '"better_supabase"."drive_nodes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_grants', '"better_supabase"."drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drives', '"better_supabase"."drive_drives"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_drive_grants', '"better_supabase"."drive_drive_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_connections', '"better_supabase"."drive_connections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.drive_node_texts', '"better_supabase"."drive_node_texts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guests', '"better_supabase"."guests"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guest_grants', '"better_supabase"."guest_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.comment_tasks', '"better_supabase"."comment_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachments', '"better_supabase"."attachments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_document_types', '"better_supabase"."attachment_document_types"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.attachment_versions', '"better_supabase"."attachment_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.retention_policies', '"better_supabase"."retention_policies"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.data_subject_requests', '"better_supabase"."data_subject_requests"', 'tenant_id', true, '{}'::text[], false),
    ('organization', 'better_supabase.sso_domains', '"better_supabase"."sso_domains"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sso_providers', '"better_supabase"."sso_providers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_users', '"better_supabase"."scim_users"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.scim_groups', '"better_supabase"."scim_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_programs', '"better_supabase"."enrollment_programs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollments', '"better_supabase"."enrollments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.enrollment_steps', '"better_supabase"."enrollment_steps"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invite_codes', '"better_supabase"."invite_codes"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.ai_projects', '"better_supabase"."ai_projects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_chats', '"better_supabase"."ai_chats"', 'tenant_id', true, array['search_tsv']::text[], true),
    ('organization', 'better_supabase.ai_tool_policies', '"better_supabase"."ai_tool_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_moderation_events', '"better_supabase"."ai_moderation_events"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_sandboxes', '"better_supabase"."ai_sandboxes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_files', '"better_supabase"."ai_files"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_documents', '"better_supabase"."ai_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_documents', '"better_supabase"."knowledge_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collections', '"better_supabase"."knowledge_collections"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.knowledge_collection_grants', '"better_supabase"."knowledge_collection_grants"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memories', '"better_supabase"."memories"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.memory_message_embeddings', '"better_supabase"."memory_message_embeddings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agents', '"better_supabase"."agents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.agent_installs', '"better_supabase"."agent_installs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.connector_servers', '"better_supabase"."connector_servers"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.connector_grants', '"better_supabase"."connector_grants"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_scheduled_tasks', '"better_supabase"."ai_scheduled_tasks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_task_runs', '"better_supabase"."ai_task_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_cache_entries', '"better_supabase"."ai_cache_entries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_provider_keys', '"better_supabase"."ai_provider_keys"', 'tenant_id', true, array['credential_ref']::text[], true),
    ('organization', 'better_supabase.ai_batches', '"better_supabase"."ai_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.ai_batch_items', '"better_supabase"."ai_batch_items"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.import_chunks', '"better_supabase"."import_chunks"', 'tenant_id', true, '{}'::text[], false),
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
    ('organization', 'better_supabase.discount_groups', '"better_supabase"."discount_groups"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_group_parties', '"better_supabase"."discount_group_parties"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.discount_rules', '"better_supabase"."discount_rules"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.approval_items', '"better_supabase"."approval_items"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.purchase_order_tax_lines', '"better_supabase"."purchase_order_tax_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.stock_counts', '"better_supabase"."stock_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.stock_count_lines', '"better_supabase"."stock_count_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.work_item_specification_lines', '"better_supabase"."work_item_specification_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.work_item_material_lines', '"better_supabase"."work_item_material_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.payment_terms', '"better_supabase"."payment_terms"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_delivery_preferences', '"better_supabase"."document_delivery_preferences"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.person_identities', '"better_supabase"."person_identities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_locations', '"better_supabase"."party_locations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_bank_accounts', '"better_supabase"."party_bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.party_channels', '"better_supabase"."party_channels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activities', '"better_supabase"."activities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.activity_subjects', '"better_supabase"."activity_subjects"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quotes', '"better_supabase"."quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_lines', '"better_supabase"."quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_versions', '"better_supabase"."quote_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_version_lines', '"better_supabase"."quote_version_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.quote_tax_lines', '"better_supabase"."quote_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoices', '"better_supabase"."invoices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_lines', '"better_supabase"."invoice_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_charges', '"better_supabase"."invoice_charges"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_levels', '"better_supabase"."invoice_dunning_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_runs', '"better_supabase"."invoice_dunning_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_run_items', '"better_supabase"."invoice_dunning_run_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_dunning_history', '"better_supabase"."invoice_dunning_history"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_allocations', '"better_supabase"."invoice_allocations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_open_items', '"better_supabase"."invoice_open_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_line_sources', '"better_supabase"."invoice_line_sources"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approval_levels', '"better_supabase"."invoice_approval_levels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_approvals', '"better_supabase"."invoice_approvals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_endpoints', '"better_supabase"."e_invoice_endpoints"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.e_invoice_deliveries', '"better_supabase"."e_invoice_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_policies', '"better_supabase"."sla_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_escalations', '"better_supabase"."sla_escalations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.sla_clocks', '"better_supabase"."sla_clocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.goals', '"better_supabase"."goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employees', '"better_supabase"."employees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_private_details', '"better_supabase"."employee_private_details"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.employee_contracts', '"better_supabase"."employee_contracts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_items', '"better_supabase"."moderation_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_reports', '"better_supabase"."moderation_reports"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_actions', '"better_supabase"."moderation_actions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_bans', '"better_supabase"."moderation_bans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_statements', '"better_supabase"."moderation_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_notices', '"better_supabase"."moderation_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_flaggers', '"better_supabase"."moderation_flaggers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.moderation_appeals', '"better_supabase"."moderation_appeals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automations', '"better_supabase"."automations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_versions', '"better_supabase"."automation_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.automation_evaluations', '"better_supabase"."automation_evaluations"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.intrastat_lines', '"better_supabase"."intrastat_lines"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.incident_regulatory_profiles', '"better_supabase"."incident_regulatory_profiles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.incident_regulatory_filings', '"better_supabase"."incident_regulatory_filings"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.timeline_entries', '"better_supabase"."timeline_entries"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.tax_codes', '"better_supabase"."tax_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_rates', '"better_supabase"."tax_rates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.invoice_tax_lines', '"better_supabase"."invoice_tax_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tax_returns', '"better_supabase"."tax_returns"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eu_sales_list_lines', '"better_supabase"."eu_sales_list_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_schedules', '"better_supabase"."accounting_recognition_schedules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_recognition_rows', '"better_supabase"."accounting_recognition_rows"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.accounting_opening_balances', '"better_supabase"."accounting_opening_balances"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budgets', '"better_supabase"."accounting_budgets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.accounting_budget_lines', '"better_supabase"."accounting_budget_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_assignments', '"better_supabase"."acknowledgement_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgements', '"better_supabase"."acknowledgements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.acknowledgement_notices', '"better_supabase"."acknowledgement_notices"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_purposes', '"better_supabase"."consent_purposes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consents', '"better_supabase"."consents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_signals', '"better_supabase"."consent_signals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.consent_receipts', '"better_supabase"."consent_receipts"', 'tenant_id', true, '{}'::text[], true),
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
    ('organization', 'better_supabase.stock_lot_links', '"better_supabase"."stock_lot_links"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_accounts', '"better_supabase"."bank_accounts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_rules', '"better_supabase"."bank_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_statements', '"better_supabase"."bank_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_transactions', '"better_supabase"."bank_transactions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bank_matches', '"better_supabase"."bank_matches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batches', '"better_supabase"."payment_batches"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payment_batch_items', '"better_supabase"."payment_batch_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meetings', '"better_supabase"."meetings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_attendees', '"better_supabase"."meeting_attendees"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_agenda_items', '"better_supabase"."meeting_agenda_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_decisions', '"better_supabase"."meeting_decisions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.meeting_action_items', '"better_supabase"."meeting_action_items"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entities', '"better_supabase"."legal_entities"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.legal_entity_settings', '"better_supabase"."legal_entity_settings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_products', '"better_supabase"."funding_products"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_awards', '"better_supabase"."funding_awards"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_deliveries', '"better_supabase"."funding_deliveries"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claims', '"better_supabase"."funding_claims"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.funding_claim_lines', '"better_supabase"."funding_claim_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_runs', '"better_supabase"."payroll_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.payroll_lines', '"better_supabase"."payroll_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plans', '"better_supabase"."maintenance_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_plan_parts', '"better_supabase"."maintenance_plan_parts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meters', '"better_supabase"."maintenance_meters"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_meter_readings', '"better_supabase"."maintenance_meter_readings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.maintenance_calibrations', '"better_supabase"."maintenance_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_usage_rights', '"better_supabase"."dam_usage_rights"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.dam_renditions', '"better_supabase"."dam_renditions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_templates', '"better_supabase"."document_templates"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.document_text_blocks', '"better_supabase"."document_text_blocks"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rendered_documents', '"better_supabase"."rendered_documents"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_methods', '"better_supabase"."lims_methods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_samples', '"better_supabase"."lims_samples"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.lims_results', '"better_supabase"."lims_results"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_cycles', '"better_supabase"."appraisal_cycles"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisals', '"better_supabase"."appraisals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_reviews', '"better_supabase"."appraisal_reviews"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_calibrations', '"better_supabase"."appraisal_calibrations"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_competencies', '"better_supabase"."appraisal_competencies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_review_ratings', '"better_supabase"."appraisal_review_ratings"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.appraisal_goals', '"better_supabase"."appraisal_goals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_waves', '"better_supabase"."pick_waves"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lists', '"better_supabase"."pick_lists"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.pick_lines', '"better_supabase"."pick_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.count_plans', '"better_supabase"."count_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.putaway_rules', '"better_supabase"."putaway_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.bin_slots', '"better_supabase"."bin_slots"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.variant_sizes', '"better_supabase"."variant_sizes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfqs', '"better_supabase"."rfqs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_lines', '"better_supabase"."rfq_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_suppliers', '"better_supabase"."rfq_suppliers"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quotes', '"better_supabase"."rfq_quotes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.rfq_quote_lines', '"better_supabase"."rfq_quote_lines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.tills', '"better_supabase"."tills"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_sessions', '"better_supabase"."till_sessions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_movements', '"better_supabase"."till_movements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_counts', '"better_supabase"."till_counts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.till_deposits', '"better_supabase"."till_deposits"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_rules', '"better_supabase"."care_rules"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.care_alerts', '"better_supabase"."care_alerts"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.periods', '"better_supabase"."periods"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.deadlines', '"better_supabase"."deadlines"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_plans', '"better_supabase"."commission_plans"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_assignments', '"better_supabase"."commission_assignments"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commissions', '"better_supabase"."commissions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.commission_statements', '"better_supabase"."commission_statements"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referral_codes', '"better_supabase"."referral_codes"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.referrals', '"better_supabase"."referrals"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prescriptions', '"better_supabase"."prescriptions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prompt_versions', '"better_supabase"."prompt_versions"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.prompt_labels', '"better_supabase"."prompt_labels"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eval_datasets', '"better_supabase"."eval_datasets"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.eval_runs', '"better_supabase"."eval_runs"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guardrail_policies', '"better_supabase"."guardrail_policies"', 'tenant_id', true, '{}'::text[], true),
    ('organization', 'better_supabase.guardrail_decisions', '"better_supabase"."guardrail_decisions"', 'tenant_id', true, '{}'::text[], true)
  ) as t(subject, name, tbl, col, purge, omit, exported)
  ) as t(subject, name, tbl, col, purge, omit, exported)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.eval_run_summary (
  run uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'total', count(*),
    'passed', count(*) filter (where x."passed"),
    'failed', count(*) filter (where not x."passed" and x."error" is null),
    'errored', count(*) filter (where x."error" is not null),
    'passRate', coalesce(round(avg(case when x."passed" then 1 else 0 end), 4), 0),
    'scorers', coalesce((
      select jsonb_object_agg(t.name, jsonb_build_object('avg', t.mean, 'passRate', t.rate))
      from (
        select e.key as name, round(avg((e.value ->> 'score')::numeric), 4) as mean,
          round(avg(case when (e.value ->> 'passed') = 'true' then 1 else 0 end), 4) as rate
        from "better_supabase"."eval_results" y, jsonb_each(y."scores") e
        where y."run_id" = eval_run_summary.run
        group by e.key
      ) t
    ), '{}'::jsonb)
  )
  from "better_supabase"."eval_results" x where x."run_id" = eval_run_summary.run;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.finish_eval_run (
  run    uuid,
  status text DEFAULT 'completed'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  if finish_eval_run.status not in ('completed', 'failed', 'cancelled') then
    raise exception 'status must be completed, failed or cancelled' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  update "better_supabase"."eval_runs" x set "status" = finish_eval_run.status, "summary" = "better_supabase"."eval_run_summary"(finish_eval_run.run), "finished_at" = now()
  where x."id" = finish_eval_run.run and x."status" = 'running'
  returning * into v_row;
  if not found then
    select x.* into v_row from "better_supabase"."eval_runs" x where x."id" = finish_eval_run.run;
    if not found then
      raise exception 'No eval run %', finish_eval_run.run using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'tenant_id', v_row."tenant_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_eval_run (
  run uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."eval_runs"%rowtype;
begin
  select x.* into v_row from "better_supabase"."eval_runs" x where x."id" = get_eval_run.run;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'dataset_id', v_row."dataset_id", 'tenant_id', v_row."tenant_id", 'prompt_name', v_row."prompt_name", 'prompt_version', v_row."prompt_version", 'model', v_row."model", 'scorers', v_row."scorers", 'status', v_row."status", 'summary', v_row."summary", 'created_at', v_row."created_at", 'finished_at', v_row."finished_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_guardrail_policy (
  agent  text,
  stage  text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."guardrail_policies"%rowtype;
begin
  select x.* into v_row from "better_supabase"."guardrail_policies" x
  where x."stage" = get_guardrail_policy.stage
    and x."agent" in (get_guardrail_policy.agent, '*')
    and (x."tenant_id" is null or x."tenant_id" = get_guardrail_policy.tenant)
  order by (x."tenant_id" is null), (x."agent" = '*')
  limit 1;
  if not found or not v_row."enabled" then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'config', v_row."config", 'enabled', v_row."enabled", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_prompt (
  name    text,
  label   text    DEFAULT 'production'::text,
  version integer DEFAULT NULL::integer,
  tenant  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
begin
  select x.* into v_row from "better_supabase"."prompt_versions" x
  where x."name" = get_prompt.name
    and (x."tenant_id" is null or x."tenant_id" = get_prompt.tenant)
    and (
      (get_prompt.version is not null and x."version" = get_prompt.version)
      or (get_prompt.version is null and exists (
        select 1 from "better_supabase"."prompt_labels" y
        where coalesce(y."tenant_id"::text, '') = coalesce(x."tenant_id"::text, '')
          and y."name" = x."name"
          and y."label" = get_prompt.label
          and y."version" = x."version"
      ))
    )
  order by (x."tenant_id" is null), x."version" desc
  limit 1;
  if not found then
    return null;
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_eval_items (
  dataset     uuid,
  pending_run uuid    DEFAULT NULL::uuid,
  after       uuid    DEFAULT NULL::uuid,
  max_rows    integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', p."id", 'dataset_id', p."dataset_id", 'input', p."input", 'expected', p."expected", 'metadata', p."metadata", 'source_chat_id', p."source_chat_id", 'source_message_id', p."source_message_id", 'created_at', p."created_at") order by p."id"), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."eval_items" x
      where x."dataset_id" = list_eval_items.dataset
        and (list_eval_items.after is null or x."id" > list_eval_items.after)
        and (list_eval_items.pending_run is null or not exists (
          select 1 from "better_supabase"."eval_results" y where y."run_id" = list_eval_items.pending_run and y."item_id" = x."id"
        ))
      order by x."id"
      limit least(greatest(coalesce(list_eval_items.max_rows, 100), 1), 1000)
    ) p
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_eval_results (
  run         uuid,
  only_failed boolean DEFAULT false,
  after       uuid    DEFAULT NULL::uuid,
  max_rows    integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('run_id', p."run_id", 'item_id', p."item_id", 'output', p."output", 'scores', p."scores", 'passed', p."passed", 'error', p."error", 'latency_ms', p."latency_ms", 'created_at', p."created_at") order by p."item_id"), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."eval_results" x
      where x."run_id" = list_eval_results.run
        and (not coalesce(list_eval_results.only_failed, false) or not x."passed")
        and (list_eval_results.after is null or x."item_id" > list_eval_results.after)
      order by x."item_id" limit least(greatest(coalesce(list_eval_results.max_rows, 100), 1), 1000)
    ) p
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_eval_runs (
  dataset  uuid,
  max_rows integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', p."id", 'dataset_id', p."dataset_id", 'tenant_id', p."tenant_id", 'prompt_name', p."prompt_name", 'prompt_version', p."prompt_version", 'model', p."model", 'scorers', p."scorers", 'status', p."status", 'summary', p."summary", 'created_at', p."created_at", 'finished_at', p."finished_at") order by p."created_at" desc), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."eval_runs" x where x."dataset_id" = list_eval_runs.dataset
      order by x."created_at" desc limit least(greatest(coalesce(list_eval_runs.max_rows, 100), 1), 1000)
    ) p
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_guardrail_decisions (
  agent    text    DEFAULT NULL::text,
  decision text    DEFAULT NULL::text,
  tenant   uuid    DEFAULT NULL::uuid,
  max_rows integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'tenant_id', q."tenant_id", 'agent', q."agent", 'stage', q."stage", 'decision', q."decision", 'reasons', q."reasons", 'chat_id', q."chat_id", 'content_hash', q."content_hash", 'created_at', q."created_at") order by q."created_at" desc), '[]'::jsonb)
    from (
      select x.* from "better_supabase"."guardrail_decisions" x
      where (list_guardrail_decisions.agent is null or x."agent" = list_guardrail_decisions.agent)
        and (list_guardrail_decisions.decision is null or x."decision" = list_guardrail_decisions.decision)
        and (list_guardrail_decisions.tenant is null or x."tenant_id" = list_guardrail_decisions.tenant)
      order by x."created_at" desc
      limit least(greatest(coalesce(list_guardrail_decisions.max_rows, 100), 1), 1000)
    ) q
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_prompt_versions (
  name   text,
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'name', x."name", 'version', x."version", 'template', x."template", 'variables', x."variables", 'created_at', x."created_at") || jsonb_build_object('labels', coalesce((
      select jsonb_agg(y."label" order by y."label") from "better_supabase"."prompt_labels" y
      where coalesce(y."tenant_id"::text, '') = coalesce(x."tenant_id"::text, '')
        and y."name" = x."name" and y."version" = x."version"
    ), '[]'::jsonb)) order by x."version" desc), '[]'::jsonb)
    from "better_supabase"."prompt_versions" x
    where x."name" = list_prompt_versions.name
      and coalesce(x."tenant_id"::text, '') = coalesce(list_prompt_versions.tenant::text, '')
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_guardrail_decisions()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer;
begin
  delete from "better_supabase"."guardrail_decisions" x where x."created_at" < now() - interval '90 days';
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_eval_result (
  run        uuid,
  item       uuid,
  output     text    DEFAULT NULL::text,
  scores     jsonb   DEFAULT '{}'::jsonb,
  error      text    DEFAULT NULL::text,
  latency_ms integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run "better_supabase"."eval_runs"%rowtype;
  v_row "better_supabase"."eval_results"%rowtype;
  v_scores jsonb := coalesce(record_eval_result.scores, '{}'::jsonb);
begin
  select x.* into v_run from "better_supabase"."eval_runs" x where x."id" = record_eval_result.run;
  if not found then
    raise exception 'No eval run %', record_eval_result.run using errcode = 'P0002', hint = 'EVAL_RUN_NOT_FOUND';
  end if;
  if v_run."status" <> 'running' then
    raise exception 'Eval run % is closed', record_eval_result.run using errcode = '55000', hint = 'EVAL_RUN_CLOSED';
  end if;
  if not exists (select 1 from "better_supabase"."eval_items" x where x."id" = record_eval_result.item and x."dataset_id" = v_run."dataset_id") then
    raise exception 'No eval item %', record_eval_result.item using errcode = 'P0002', hint = 'EVAL_ITEM_NOT_FOUND';
  end if;
  if jsonb_typeof(v_scores) <> 'object' then
    raise exception 'scores must be a JSON object' using errcode = '22023', hint = 'EVAL_INVALID';
  end if;
  insert into "better_supabase"."eval_results" ("run_id", "item_id", "output", "scores", "passed", "error", "latency_ms")
  values (record_eval_result.run, record_eval_result.item, record_eval_result.output, v_scores,
    record_eval_result.error is null and not exists (select 1 from jsonb_each(v_scores) e where (e.value ->> 'passed') is distinct from 'true'),
    record_eval_result.error, record_eval_result.latency_ms)
  on conflict ("run_id", "item_id") do update set
    "output" = excluded."output", "scores" = excluded."scores", "passed" = excluded."passed",
    "error" = excluded."error", "latency_ms" = excluded."latency_ms", "created_at" = now()
  returning * into v_row;
  return jsonb_build_object('run_id', v_row."run_id", 'item_id', v_row."item_id", 'output', v_row."output", 'scores', v_row."scores", 'passed', v_row."passed", 'error', v_row."error", 'latency_ms', v_row."latency_ms", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_guardrail_decision (
  agent        text,
  stage        text,
  decision     text,
  reasons      jsonb DEFAULT '[]'::jsonb,
  tenant       uuid  DEFAULT NULL::uuid,
  chat         text  DEFAULT NULL::text,
  content_hash text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."guardrail_decisions"%rowtype;
begin
  insert into "better_supabase"."guardrail_decisions" ("tenant_id", "agent", "stage", "decision", "reasons", "chat_id", "content_hash")
  values (record_guardrail_decision.tenant, record_guardrail_decision.agent, record_guardrail_decision.stage, record_guardrail_decision.decision, coalesce(record_guardrail_decision.reasons, '[]'::jsonb), record_guardrail_decision.chat, record_guardrail_decision.content_hash)
  returning * into v_row;
  if v_row."decision" = 'block' then
    perform "better_supabase".emit_event('guardrail.blocked', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'decisionId', v_row."id", 'agent', v_row."agent", 'stage', v_row."stage", 'reasons', v_row."reasons"), 'guardrail-decisions/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/ai-guardrails');
  perform better_supabase.audit_event(
    event_type => 'guardrail.blocked',
    category => 'ai',
    target_type => 'guardrail_decision',
    record_id => v_row."id"::text,
    target_label => v_row."agent" || '/' || v_row."stage",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'decisionId', v_row."id", 'agent', v_row."agent", 'stage', v_row."stage", 'reasons', v_row."reasons")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'decision', v_row."decision", 'reasons', v_row."reasons", 'chat_id', v_row."chat_id", 'content_hash', v_row."content_hash", 'created_at', v_row."created_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_guardrail_policy (
  agent   text,
  stage   text,
  config  jsonb,
  tenant  uuid    DEFAULT NULL::uuid,
  enabled boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."guardrail_policies"%rowtype;
begin
  if jsonb_typeof(set_guardrail_policy.config) is distinct from 'object' then
    raise exception 'config must be a JSON object' using errcode = '22023', hint = 'GUARDRAIL_INVALID';
  end if;
  insert into "better_supabase"."guardrail_policies" ("tenant_id", "agent", "stage", "config", "enabled")
  values (set_guardrail_policy.tenant, set_guardrail_policy.agent, set_guardrail_policy.stage, set_guardrail_policy.config, coalesce(set_guardrail_policy.enabled, true))
  on conflict ((coalesce("tenant_id"::text, '')), "agent", "stage") do update set
    "config" = excluded."config", "enabled" = excluded."enabled", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'agent', v_row."agent", 'stage', v_row."stage", 'config', v_row."config", 'enabled', v_row."enabled", 'updated_at', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_prompt_label (
  name    text,
  label   text,
  version integer,
  tenant  uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."prompt_versions"%rowtype;
begin
  select x.* into v_row from "better_supabase"."prompt_versions" x
  where x."name" = set_prompt_label.name
    and x."version" = set_prompt_label.version
    and coalesce(x."tenant_id"::text, '') = coalesce(set_prompt_label.tenant::text, '');
  if not found then
    raise exception 'No version % of prompt %', set_prompt_label.version, set_prompt_label.name using errcode = 'P0002', hint = 'PROMPT_NOT_FOUND';
  end if;
  insert into "better_supabase"."prompt_labels" ("tenant_id", "name", "label", "version")
  values (set_prompt_label.tenant, set_prompt_label.name, set_prompt_label.label, set_prompt_label.version)
  on conflict ((coalesce("tenant_id"::text, '')), "name", "label") do update set
    "version" = excluded."version",
    "updated_at" = now();
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'name', v_row."name", 'version', v_row."version", 'template', v_row."template", 'variables', v_row."variables", 'created_at', v_row."created_at");
end;
$function$;

ALTER TABLE "better_supabase"."eval_items"
  ADD CONSTRAINT "eval_items_dataset_id_fkey" FOREIGN KEY (dataset_id) REFERENCES better_supabase.eval_datasets(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."eval_results"
  ADD CONSTRAINT "eval_results_item_id_fkey" FOREIGN KEY (item_id) REFERENCES better_supabase.eval_items(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."eval_runs"
  ADD CONSTRAINT "eval_runs_dataset_id_fkey" FOREIGN KEY (dataset_id) REFERENCES better_supabase.eval_datasets(id) ON DELETE CASCADE;

ALTER TABLE "better_supabase"."eval_results"
  ADD CONSTRAINT "eval_results_run_id_fkey" FOREIGN KEY (run_id) REFERENCES better_supabase.eval_runs(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX bsb_eval_datasets_key ON better_supabase.eval_datasets USING btree (COALESCE((tenant_id)::text, ''::text), name);

CREATE UNIQUE INDEX bsb_eval_items_source_key ON better_supabase.eval_items USING btree (dataset_id, source_chat_id, source_message_id)
  WHERE (source_chat_id IS NOT NULL);

CREATE UNIQUE INDEX bsb_guardrail_policies_key ON better_supabase.guardrail_policies USING btree (COALESCE((tenant_id)::text, ''::text), agent, stage);

CREATE UNIQUE INDEX bsb_prompt_labels_key ON better_supabase.prompt_labels USING btree (COALESCE((tenant_id)::text, ''::text), name, label);

CREATE UNIQUE INDEX bsb_prompt_versions_key ON better_supabase.prompt_versions USING btree (COALESCE((tenant_id)::text, ''::text), name, VERSION);

CREATE INDEX eval_items_dataset_idx ON better_supabase.eval_items USING btree (dataset_id, id);

CREATE INDEX eval_results_item_idx ON better_supabase.eval_results USING btree (item_id);

CREATE INDEX eval_runs_dataset_idx ON better_supabase.eval_runs USING btree (dataset_id, created_at DESC);

CREATE INDEX guardrail_decisions_agent_idx ON better_supabase.guardrail_decisions USING btree (agent, created_at DESC);

CREATE INDEX guardrail_decisions_tenant_idx ON better_supabase.guardrail_decisions USING btree (tenant_id, created_at DESC, id DESC);

CREATE INDEX prompt_labels_tenant_idx ON better_supabase.prompt_labels USING btree (tenant_id);

CREATE INDEX prompt_versions_tenant_idx ON better_supabase.prompt_versions USING btree (tenant_id);

REVOKE ALL ON FUNCTION "api"."add_eval_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_eval_items"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."add_eval_items_from_feedback"(uuid, integer, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."add_eval_items_from_feedback"(uuid, integer, timestamp WITH time zone, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."compare_eval_runs"(uuid, uuid, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."compare_eval_runs"(uuid, uuid, numeric) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_eval_dataset"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_eval_dataset"(text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_eval_run"(uuid, text, integer, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_eval_run"(uuid, text, integer, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_prompt_version"(text, text, uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_prompt_version"(text, text, uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."eval_run_summary"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."eval_run_summary"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."finish_eval_run"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."finish_eval_run"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_eval_run"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_eval_run"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_guardrail_policy"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_guardrail_policy"(text, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."get_prompt"(text, text, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_prompt"(text, text, integer, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_eval_items"(uuid, uuid, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_eval_items"(uuid, uuid, uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_eval_results"(uuid, boolean, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_eval_results"(uuid, boolean, uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_eval_runs"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_eval_runs"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_guardrail_decisions"(text, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_guardrail_decisions"(text, text, uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."list_prompt_versions"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_prompt_versions"(text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."purge_guardrail_decisions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_guardrail_decisions"() TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_eval_result"(uuid, uuid, text, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_eval_result"(uuid, uuid, text, jsonb, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."set_prompt_label"(text, text, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_prompt_label"(text, text, integer, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_eval_items"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_eval_items"(uuid, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."add_eval_items_from_feedback"(uuid, integer, timestamp WITH time zone, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."add_eval_items_from_feedback"(uuid, integer, timestamp WITH time zone, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."compare_eval_runs"(uuid, uuid, numeric) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."compare_eval_runs"(uuid, uuid, numeric) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_eval_dataset"(text, uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_eval_dataset"(text, uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_eval_run"(uuid, text, integer, text, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_eval_run"(uuid, text, integer, text, jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_prompt_version"(text, text, uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_prompt_version"(text, text, uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."eval_run_summary"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."eval_run_summary"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."finish_eval_run"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."finish_eval_run"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_eval_run"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_eval_run"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_guardrail_policy"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_guardrail_policy"(text, text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_prompt"(text, text, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_prompt"(text, text, integer, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_eval_items"(uuid, uuid, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_eval_items"(uuid, uuid, uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_eval_results"(uuid, boolean, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_eval_results"(uuid, boolean, uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_eval_runs"(uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_eval_runs"(uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_guardrail_decisions"(text, text, uuid, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_guardrail_decisions"(text, text, uuid, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_prompt_versions"(text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_prompt_versions"(text, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_guardrail_decisions"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_guardrail_decisions"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_eval_result"(uuid, uuid, text, jsonb, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_eval_result"(uuid, uuid, text, jsonb, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_guardrail_decision"(text, text, text, jsonb, uuid, text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_guardrail_policy"(text, text, jsonb, uuid, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_prompt_label"(text, text, integer, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_prompt_label"(text, text, integer, uuid) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."eval_datasets" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."eval_items" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."eval_results" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."eval_runs" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."guardrail_decisions" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."guardrail_policies" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."prompt_labels" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."prompt_versions" TO "service_role";
