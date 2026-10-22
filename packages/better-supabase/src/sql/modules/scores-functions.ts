import type { ModuleContext } from "../context.ts";

import { fail, pageSize, SERVICE_CALLER, userGrant } from "../shared.ts";
import { moduleOperations } from "./access-model.ts";

const MAX_BANDS = 10;

function limitOf(ctx: ModuleContext, name: string, fallback: number): string {
  const value = ctx.number(name, fallback);

  if (!Number.isInteger(value) || value < 1 || value > 1000) {
    throw new TypeError(
      `blocks.scores.options.${name} must be a whole number from 1 to 1000`,
    );
  }

  return String(value);
}

/** The scores module's functions. */
export function scoresFunctions(ctx: ModuleContext): string {
  const models = ctx.table("models");
  const versions = ctx.table("versions");
  const scores = ctx.table("scores");
  const m = (column: string): string => ctx.col("models", column);
  const v = (column: string): string => ctx.col("versions", column);
  const s = (column: string): string => ctx.col("scores", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("scores");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const compute = ctx.permission("compute", permissions.compute);
  const rules = ctx.of("rules");
  const maxRules = limitOf(ctx, "maxRules", 100);
  const maxMetrics = limitOf(ctx, "maxMetrics", 50);

  const reactions =
    ctx.installed("reactions") && ctx.of("reactions").manages
      ? ctx.of("reactions")
      : undefined;

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("SCORES_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("SCORES_MODEL_INVALID", message, "22023");

  const modelMissing = fail(
    "SCORES_MODEL_NOT_FOUND",
    "score model not found",
    "P0002",
  );

  const modelJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'key', ${row}.${m("key")}, 'name', ${row}.${m("name")}, 'description', ${row}.${m("description")}, 'subjectType', ${row}.${m("subjectType")}, 'rules', ${row}.${m("rules")}, 'metrics', ${row}.${m("metrics")}, 'bands', ${row}.${m("bands")}, 'enabled', ${row}.${m("enabled")}, 'version', ${row}.${m("version")}, 'createdBy', ${row}.${m("createdBy")}, 'createdAt', ${row}.${m("createdAt")}, 'updatedAt', ${row}.${m("updatedAt")})`;

  const scoreJson = (row: string, key: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'modelId', ${row}.${s("model")}, 'modelKey', ${key}, 'modelVersion', ${row}.${s("modelVersion")}, 'subjectType', ${row}.${s("subjectType")}, 'subjectId', ${row}.${s("subjectId")}, 'score', ${row}.${s("score")}, 'band', ${row}.${s("band")}, 'breakdown', ${row}.${s("breakdown")}, 'current', ${row}.${s("current")}, 'computedAt', ${row}.${s("computedAt")})`;

  const modelRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${m("tenant")}, 'id', ${row}.${m("id")}, 'key', ${row}.${m("key")}, 'subjectType', ${row}.${m("subjectType")}, 'version', ${row}.${m("version")})`,
      subject: `'score-models/' || ${row}.${m("id")}::text`,
      tenant: `${row}.${m("tenant")}`,
      audit: {
        category: "data",
        targetType: "score_model",
        recordId: `${row}.${m("id")}::text`,
        targetLabel: `${row}.${m("name")}`,
        summary: `'${summary}'`,
      },
    });

  const votes = reactions
    ? `coalesce((select y.${reactions.col("scores", "score")} from ${reactions.table("scores")} y where y.${reactions.col("scores", "tenant")} = compute_score.tenant and y.${reactions.col("scores", "subjectType")} = compute_score.subject_type and y.${reactions.col("scores", "subjectId")} = compute_score.subject_id), 0)`
    : "0";

  const sources = reactions ? "('field', 'votes')" : "('field')";

  return `-- Creates or changes a score model. model is { id?, version?, key, name,
-- description, subjectType, rules, metrics, bands, enabled }; keys left out
-- keep their value. Every change saves a new version. version, when given,
-- must be the stored one.
create or replace function ${fn("save_score_model")}(tenant ${idType}, model jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_id uuid;
  v_old ${models};
  v_row ${models};
  v_key text;
  v_name text;
  v_description text;
  v_subject_type text;
  v_rules jsonb;
  v_metrics jsonb;
  v_bands jsonb;
  v_enabled boolean;
  v_fields jsonb;
  v_entry jsonb;
begin
  if not ${allowed("save_score_model.tenant", manage)} then
    ${forbidden("not allowed to manage score models")}
  end if;
  if jsonb_typeof(model) is distinct from 'object' then
    ${invalid("model must be an object")}
  end if;
  v_id := nullif(model ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from ${models} x where x.${m("id")} = v_id and x.${m("tenant")} = save_score_model.tenant for update;
    if v_old.${m("id")} is null then
      ${modelMissing}
    end if;
    if model ? 'version' and (model ->> 'version')::integer is distinct from v_old.${m("version")} then
      ${fail("SCORES_MODEL_CONFLICT", "the score model changed since it was read", "40001")}
    end if;
    if model ? 'subjectType' and model ->> 'subjectType' is distinct from v_old.${m("subjectType")} then
      ${invalid("a score model's subject type can't change")}
    end if;
  end if;
  v_key := coalesce(v_old.${m("key")}, model ->> 'key');
  v_name := coalesce(nullif(trim(model ->> 'name'), ''), v_old.${m("name")});
  v_description := case when model ? 'description' then nullif(trim(model ->> 'description'), '') else v_old.${m("description")} end;
  v_subject_type := coalesce(v_old.${m("subjectType")}, model ->> 'subjectType');
  v_rules := coalesce(model -> 'rules', v_old.${m("rules")}, '[]'::jsonb);
  v_metrics := coalesce(model -> 'metrics', v_old.${m("metrics")}, '[]'::jsonb);
  v_bands := coalesce(model -> 'bands', v_old.${m("bands")}, '[]'::jsonb);
  v_enabled := coalesce((model ->> 'enabled')::boolean, v_old.${m("enabled")}, true);
  if v_key is null or v_key !~ '^[a-z][a-z0-9_-]{0,62}$' then
    ${invalid("a score model needs a key such as lead or health")}
  end if;
  if v_name is null or length(v_name) > 200 then
    ${invalid("a score model needs a name of at most 200 characters")}
  end if;
  if v_subject_type is null or v_subject_type !~ '^[a-z][a-z0-9_]{0,62}$' then
    ${invalid("a score model needs a subject type")}
  end if;
  if jsonb_typeof(v_rules) is distinct from 'array' or jsonb_array_length(v_rules) > ${maxRules} then
    ${invalid(`rules must be an array of at most ${maxRules} entries`)}
  end if;
  if jsonb_typeof(v_metrics) is distinct from 'array' or jsonb_array_length(v_metrics) > ${maxMetrics} then
    ${invalid(`metrics must be an array of at most ${maxMetrics} entries`)}
  end if;
  if jsonb_typeof(v_bands) is distinct from 'array' or jsonb_array_length(v_bands) > ${String(MAX_BANDS)} then
    ${invalid(`bands must be an array of at most ${String(MAX_BANDS)} entries`)}
  end if;
  v_fields := ${rules.fn("rule_field_map")}(v_subject_type);
  for v_entry in select x.value from jsonb_array_elements(v_rules) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or jsonb_typeof(v_entry -> 'points') is distinct from 'number'
      or jsonb_typeof(v_entry -> 'conditions') is distinct from 'object' then
      ${invalid("every rule needs an id, conditions and a number of points")}
    end if;
    if v_fields = '{}'::jsonb then
      ${fail("SCORES_SUBJECT_UNKNOWN", "no rule fields for this subject type; sync them first", "22023")}
    end if;
    perform ${rules.fn("rule_check")}(v_entry -> 'conditions', v_fields, 1);
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_metrics) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'id'), 0) not between 1 and 64
      or coalesce(v_entry ->> 'source', 'field') not in ${sources}
      or (v_entry ? 'weight' and jsonb_typeof(v_entry -> 'weight') is distinct from 'number')
      or (v_entry ? 'cap' and (jsonb_typeof(v_entry -> 'cap') is distinct from 'number' or (v_entry ->> 'cap')::numeric < 0)) then
      ${invalid(`every metric needs an id, a source ${reactions ? "(field or votes)" : "(field)"}, and a numeric weight and cap`)}
    end if;
    if coalesce(v_entry ->> 'source', 'field') = 'field'
      and (v_fields -> (v_entry ->> 'field')) ->> 'type' is distinct from 'number' then
      ${invalid("a field metric names a number field of the subject type")}
    end if;
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_bands) x loop
    if jsonb_typeof(v_entry) is distinct from 'object' or coalesce(length(v_entry ->> 'label'), 0) not between 1 and 60
      or jsonb_typeof(v_entry -> 'min') is distinct from 'number' then
      ${invalid("every band needs a label and a min score")}
    end if;
  end loop;
  v_bands := coalesce((
    select jsonb_agg(jsonb_build_object('label', x.value ->> 'label', 'min', (x.value ->> 'min')::numeric) order by (x.value ->> 'min')::numeric desc)
    from jsonb_array_elements(v_bands) x
  ), '[]'::jsonb);
  if v_old.${m("id")} is null then
    if exists (select 1 from ${models} x where x.${m("tenant")} = save_score_model.tenant and x.${m("key")} = v_key) then
      ${fail("SCORES_MODEL_KEY_TAKEN", "a score model with this key already exists", "23505")}
    end if;
    insert into ${models} (${m("tenant")}, ${m("key")}, ${m("name")}, ${m("description")}, ${m("subjectType")}, ${m("rules")}, ${m("metrics")}, ${m("bands")}, ${m("enabled")}, ${m("createdBy")})
    values (save_score_model.tenant, v_key, v_name, v_description, v_subject_type, v_rules, v_metrics, v_bands, v_enabled, auth.uid())
    returning * into v_row;
  elsif v_old.${m("name")} = v_name and v_old.${m("description")} is not distinct from v_description
    and v_old.${m("rules")} = v_rules and v_old.${m("metrics")} = v_metrics
    and v_old.${m("bands")} = v_bands and v_old.${m("enabled")} = v_enabled then
    return ${modelJson("v_old")};
  else
    update ${models} x set
      ${m("name")} = v_name,
      ${m("description")} = v_description,
      ${m("rules")} = v_rules,
      ${m("metrics")} = v_metrics,
      ${m("bands")} = v_bands,
      ${m("enabled")} = v_enabled,
      ${m("version")} = x.${m("version")} + case when x.${m("rules")} = v_rules and x.${m("metrics")} = v_metrics and x.${m("bands")} = v_bands then 0 else 1 end,
      ${m("updatedAt")} = now()
    where x.${m("id")} = v_old.${m("id")}
    returning * into v_row;
  end if;
  insert into ${versions} (${v("model")}, ${v("version")}, ${v("tenant")}, ${v("rules")}, ${v("metrics")}, ${v("bands")}, ${v("savedBy")})
  values (v_row.${m("id")}, v_row.${m("version")}, v_row.${m("tenant")}, v_row.${m("rules")}, v_row.${m("metrics")}, v_row.${m("bands")}, auth.uid())
  on conflict do nothing;
  ${modelRecord("score_model.saved", "v_row", "saved score model")}
  return ${modelJson("v_row")};
end;
$$;
${userGrant(`${fn("save_score_model")}(${idType}, jsonb)`)}

-- An organization's score models, by key, for one subject type when given.
create or replace function ${fn("list_score_models")}(tenant ${idType}, subject_type text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_score_models.tenant", read)} then
    ${forbidden("not allowed to read scores")}
  end if;
  return coalesce((
    select jsonb_agg(${modelJson("x")} order by x.${m("key")})
    from ${models} x
    where x.${m("tenant")} = list_score_models.tenant
      and (list_score_models.subject_type is null or x.${m("subjectType")} = list_score_models.subject_type)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_score_models")}(${idType}, text)`)}

-- One score model with its saved versions, or null when the caller can't read it.
create or replace function ${fn("get_score_model")}(model_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${models};
begin
  select * into v_row from ${models} x where x.${m("id")} = get_score_model.model_id;
  if not found or not ${allowed(`v_row.${m("tenant")}`, read)} then
    return null;
  end if;
  return ${modelJson("v_row")} || jsonb_build_object('versions', coalesce((
    select jsonb_agg(jsonb_build_object('version', y.${v("version")}, 'rules', y.${v("rules")}, 'metrics', y.${v("metrics")}, 'bands', y.${v("bands")}, 'savedBy', y.${v("savedBy")}, 'savedAt', y.${v("savedAt")}) order by y.${v("version")} desc)
    from ${versions} y where y.${v("model")} = v_row.${m("id")}
  ), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("get_score_model")}(uuid)`)}

-- Removes a score model with its versions and scores; false when there is none.
create or replace function ${fn("delete_score_model")}(model_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${models};
begin
  select * into v_row from ${models} x where x.${m("id")} = delete_score_model.model_id for update;
  if not found then
    return false;
  end if;
  if not ${allowed(`v_row.${m("tenant")}`, manage)} then
    ${forbidden("not allowed to manage score models")}
  end if;
  delete from ${models} x where x.${m("id")} = v_row.${m("id")};
  ${modelRecord("score_model.deleted", "v_row", "deleted score model")}
  return true;
end;
$$;
${userGrant(`${fn("delete_score_model")}(uuid)`)}

-- Scores a subject with an enabled model. subject holds the record's fields
-- the way rule_evaluate reads them. Rules add their points when their tree
-- matches; metrics add their value times weight, capped at cap either way.
-- The first band whose min the total reaches names it. A score that differs
-- from the current one (or comes from a newer model version) is saved as the
-- new current score and emits score.changed; otherwise the current one is
-- returned.
create or replace function ${fn("compute_score")}(tenant ${idType}, model_key text, subject_type text, subject_id text, subject jsonb, time_zone text default 'UTC')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_model ${models};
  v_fields jsonb;
  v_entry jsonb;
  v_matched boolean;
  v_value numeric;
  v_points numeric;
  v_cap numeric;
  v_total numeric := 0;
  v_rules jsonb := '[]'::jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_band text;
  v_breakdown jsonb;
  v_current ${scores};
  v_row ${scores};
begin
  if not ${allowed("compute_score.tenant", compute)} then
    ${forbidden("not allowed to compute scores")}
  end if;
  select * into v_model from ${models} x where x.${m("tenant")} = compute_score.tenant and x.${m("key")} = compute_score.model_key;
  if not found then
    ${modelMissing}
  end if;
  if not v_model.${m("enabled")} then
    ${fail("SCORES_MODEL_DISABLED", "the score model is turned off", "55000")}
  end if;
  if compute_score.subject_type is distinct from v_model.${m("subjectType")} then
    ${fail("SCORES_SUBJECT_MISMATCH", "the score model scores another subject type", "22023")}
  end if;
  if jsonb_typeof(compute_score.subject) is distinct from 'object' or compute_score.subject_id is null then
    ${fail("SCORES_SUBJECT_INVALID", "subject must be an object and subject_id set", "22023")}
  end if;
  v_fields := ${rules.fn("rule_field_map")}(v_model.${m("subjectType")});
  for v_entry in select x.value from jsonb_array_elements(v_model.${m("rules")}) x loop
    v_matched := coalesce(${rules.fn("rule_matches")}(v_entry -> 'conditions', compute_score.subject, v_fields, coalesce(compute_score.time_zone, 'UTC'), now()), false);
    v_points := case when v_matched then (v_entry ->> 'points')::numeric else 0 end;
    v_total := v_total + v_points;
    v_rules := v_rules || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'matched', v_matched, 'points', v_points));
  end loop;
  for v_entry in select x.value from jsonb_array_elements(v_model.${m("metrics")}) x loop
    if v_entry ->> 'source' = 'votes' then
      v_value := ${votes};
    else
      v_value := ${rules.fn("rule_numeric")}(compute_score.subject #> string_to_array((v_fields -> (v_entry ->> 'field')) ->> 'column', '.'));
    end if;
    v_points := coalesce(v_value, 0) * coalesce((v_entry ->> 'weight')::numeric, 1);
    v_cap := (v_entry ->> 'cap')::numeric;
    if v_cap is not null then
      v_points := greatest(least(v_points, v_cap), -v_cap);
    end if;
    v_total := v_total + v_points;
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object('id', v_entry ->> 'id', 'label', v_entry ->> 'label', 'value', v_value, 'points', v_points));
  end loop;
  v_total := round(v_total, 4);
  select x.value ->> 'label' into v_band
  from jsonb_array_elements(v_model.${m("bands")}) x
  where v_total >= (x.value ->> 'min')::numeric
  order by (x.value ->> 'min')::numeric desc
  limit 1;
  v_breakdown := jsonb_build_object('rules', v_rules, 'metrics', v_metrics);
  select * into v_current from ${scores} x
  where x.${s("model")} = v_model.${m("id")} and x.${s("subjectType")} = compute_score.subject_type
    and x.${s("subjectId")} = compute_score.subject_id and x.${s("current")}
  for update;
  if found and v_current.${s("score")} = v_total and v_current.${s("band")} is not distinct from v_band
    and v_current.${s("modelVersion")} = v_model.${m("version")} and v_current.${s("breakdown")} = v_breakdown then
    return ${scoreJson("v_current", `v_model.${m("key")}`)} || jsonb_build_object('changed', false);
  end if;
  update ${scores} x set ${s("current")} = false where x.${s("id")} = v_current.${s("id")};
  insert into ${scores} (${s("tenant")}, ${s("model")}, ${s("modelVersion")}, ${s("subjectType")}, ${s("subjectId")}, ${s("score")}, ${s("band")}, ${s("breakdown")}, ${s("computedAt")})
  values (compute_score.tenant, v_model.${m("id")}, v_model.${m("version")}, compute_score.subject_type, compute_score.subject_id, v_total, v_band, v_breakdown, clock_timestamp())
  returning * into v_row;
  ${ctx.emit({
    type: "score.changed",
    payload: `jsonb_build_object('organizationId', v_row.${s("tenant")}, 'modelId', v_row.${s("model")}, 'modelKey', v_model.${m("key")}, 'subjectType', v_row.${s("subjectType")}, 'subjectId', v_row.${s("subjectId")}, 'score', v_row.${s("score")}, 'previousScore', v_current.${s("score")}, 'band', v_row.${s("band")}, 'previousBand', v_current.${s("band")})`,
    subject: `'scores/' || v_row.${s("id")}::text`,
    tenant: `v_row.${s("tenant")}`,
  })}
  return ${scoreJson("v_row", `v_model.${m("key")}`)} || jsonb_build_object('changed', true);
end;
$$;
${userGrant(`${fn("compute_score")}(${idType}, text, text, text, jsonb, text)`)}

-- A subject's current scores, one per model, by model key.
create or replace function ${fn("subject_scores")}(tenant ${idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("subject_scores.tenant", read)} then
    ${forbidden("not allowed to read scores")}
  end if;
  return coalesce((
    select jsonb_agg(${scoreJson("x", `y.${m("key")}`)} || jsonb_build_object('modelName', y.${m("name")}) order by y.${m("key")})
    from ${scores} x join ${models} y on y.${m("id")} = x.${s("model")}
    where x.${s("tenant")} = subject_scores.tenant and x.${s("subjectType")} = subject_scores.subject_type
      and x.${s("subjectId")} = subject_scores.subject_id and x.${s("current")}
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("subject_scores")}(${idType}, text, text)`)}

-- A subject's scores under one model, newest first.
create or replace function ${fn("score_history")}(tenant ${idType}, model_key text, subject_type text, subject_id text, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("score_history.tenant", read)} then
    ${forbidden("not allowed to read scores")}
  end if;
  return coalesce((
    select jsonb_agg(${scoreJson("z", "z.model_key")} order by z.${s("computedAt")} desc, z.${s("id")} desc)
    from (
      select x.*, y.${m("key")} as model_key
      from ${scores} x join ${models} y on y.${m("id")} = x.${s("model")}
      where x.${s("tenant")} = score_history.tenant and y.${m("key")} = score_history.model_key
        and x.${s("subjectType")} = score_history.subject_type and x.${s("subjectId")} = score_history.subject_id
      order by x.${s("computedAt")} desc, x.${s("id")} desc
      limit ${pageSize("score_history.page_size", 50, 200)}
    ) z
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("score_history")}(${idType}, text, text, text, integer)`)}

-- The highest current scores under one model, in one band or from a minimum
-- score when given.
create or replace function ${fn("top_scores")}(tenant ${idType}, model_key text, band text default null, min_score numeric default null, page_size integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("top_scores.tenant", read)} then
    ${forbidden("not allowed to read scores")}
  end if;
  return coalesce((
    select jsonb_agg(${scoreJson("z", "top_scores.model_key")} order by z.${s("score")} desc, z.${s("computedAt")} desc)
    from (
      select x.*
      from ${scores} x join ${models} y on y.${m("id")} = x.${s("model")}
      where x.${s("tenant")} = top_scores.tenant and y.${m("key")} = top_scores.model_key and x.${s("current")}
        and (top_scores.band is null or x.${s("band")} = top_scores.band)
        and (top_scores.min_score is null or x.${s("score")} >= top_scores.min_score)
      order by x.${s("score")} desc, x.${s("computedAt")} desc
      limit ${pageSize("top_scores.page_size", 50, 200)}
    ) z
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("top_scores")}(${idType}, text, text, numeric, integer)`)}
`;
}
