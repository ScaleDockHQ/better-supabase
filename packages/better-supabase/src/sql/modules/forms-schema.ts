import type { ModuleContext } from "../context.ts";

import {
  CUSTOM_FIELD_FORM_TYPES,
  RATING_BOUNDS,
} from "../../core/contracts/field-formats.ts";
import {
  FORM_DEFINITION_SCHEMA,
  FORM_MAX_LENGTH,
  FORM_SCHEMA_DIALECT,
  NPS_MAX,
  UNSCORED_FIELD_TYPES,
} from "../../core/contracts/form-definition.ts";
import { sqlString } from "../../core/template.ts";

const textMax = (type: keyof typeof FORM_MAX_LENGTH): string =>
  String(FORM_MAX_LENGTH[type]);

const definitionInvalid = (errors: string): string =>
  `raise exception 'the form definition is invalid: %', array_to_string(${errors}, '; ')
      using errcode = '22023', detail = to_jsonb(${errors})::text, hint = 'FORM_DEFINITION_INVALID';`;

/**
 * The form field type a custom field type answers as
 * (`CUSTOM_FIELD_FORM_TYPES`).
 */
function formTypeOf(type: string): string {
  const renamed = Object.entries(CUSTOM_FIELD_FORM_TYPES)
    .filter(([custom, form]) => custom !== form)
    .map(
      ([custom, form]) => `when ${sqlString(custom)} then ${sqlString(form)}`,
    )
    .join(" ");

  return `case ${type} ${renamed} else ${type} end`;
}

/** The bounds a rating field answers within, unless the form field sets its own. */
function formBoundsOf(type: string): string {
  const [min, max] = RATING_BOUNDS;

  return `case when ${type} = 'rating' then jsonb_build_object('min', ${String(min)}, 'max', ${String(max)}) else '{}'::jsonb end`;
}

function customFieldResolve(ctx: ModuleContext): string {
  const problem = (message: string): string => `v_problem := ${message};
        exit;`;

  if (!ctx.installed("custom-fields")) {
    return `if v_field ? 'customField' then
        ${problem(`format('field %s: customField needs the custom-fields module', v_field ->> 'key')`)}
      end if;`;
  }

  const cf = ctx.of("custom-fields");
  const d = (column: string): string => cf.col("definitions", column);
  const o = (column: string): string => cf.col("options", column);

  // Managed custom-fields stores only option ids; an adopted options table may exist.
  // A constant query would make plpgsql_check resolve the table when it is missing.
  const options = cf.hasTable("options")
    ? `
        if v_custom ->> 'type' in ('option', 'multi') and not v_field ? 'options' and to_regclass(${sqlString(cf.table("options"))}) is not null then
          execute format(${sqlString(`select jsonb_agg(jsonb_build_object('value', o.${o("value")}, 'label', o.${o("label")}) order by o.${o("value")}) from %s o where o.${o("definition")} = $1`)}, to_regclass(${sqlString(cf.table("options"))}))
            into v_options using (v_field ->> 'customField')::uuid;
          v_custom := v_custom || jsonb_strip_nulls(jsonb_build_object('options', v_options));
        end if;`
    : "";

  return `if v_field ? 'customField' then
        select jsonb_strip_nulls(jsonb_build_object('label', d.${d("label")}, 'type', ${formTypeOf(`d.${d("type")}`)}, 'required', d.${d("required")}))
            || ${formBoundsOf(`d.${d("type")}`)}
          into v_custom
          from ${cf.table("definitions")} d
          where d.${d("id")} = (v_field ->> 'customField')::uuid and d.${d("tenant")} = form_resolve.tenant;
        if v_custom is null then
          ${problem(`format('field %s: customField %s is not a field definition in this organization', v_field ->> 'key', v_field ->> 'customField')`)}
        end if;${options}
        v_field := v_custom || v_field;
      end if;`;
}

/**
 * The SQL twins of `fieldSchema`, `conditionSchema`, `formSchema` and the
 * definition checks in `core/contracts/form-definition.ts`. The integration
 * test asserts both produce the same schema.
 */
export function formSchemaFunctions(ctx: ModuleContext): string {
  const fn = (name: string): string => ctx.fn(name);

  return `-- The schema of one field's answer. Mirrors fieldSchema in
-- core/contracts/form-definition.ts.
create or replace function ${fn("form_field_schema")}(field jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_type text := field ->> 'type';
  -- required only asks for the key, so an empty answer needs its own floor.
  v_floor jsonb := case when field -> 'required' = 'true'::jsonb then '1'::jsonb end;
  v_values jsonb;
  v_out jsonb;
begin
  select coalesce(jsonb_agg(o.value -> 'value' order by o.ord), '[]'::jsonb) into v_values
    from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) with ordinality as o(value, ord);
  v_out := case v_type
    when 'text' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '${textMax("text")}'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'textarea' then jsonb_build_object('type', 'string', 'maxLength', coalesce(field -> 'maxLength', '${textMax("textarea")}'::jsonb))
      || jsonb_strip_nulls(jsonb_build_object('minLength', coalesce(field -> 'minLength', v_floor), 'pattern', field -> 'pattern'))
    when 'email' then jsonb_build_object('type', 'string', 'format', 'email', 'maxLength', ${textMax("email")})
    when 'url' then jsonb_build_object('type', 'string', 'format', 'uri', 'maxLength', ${textMax("url")})
    when 'number' then jsonb_build_object('type', 'number') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'integer' then jsonb_build_object('type', 'integer') || jsonb_strip_nulls(jsonb_build_object('minimum', field -> 'min', 'maximum', field -> 'max'))
    when 'date' then '{"type": "string", "format": "date"}'::jsonb
    when 'bool' then '{"type": "boolean"}'::jsonb
    when 'consent' then '{"type": "boolean", "const": true}'::jsonb
    when 'option' then jsonb_build_object('type', 'string', 'enum', v_values)
    when 'multi' then jsonb_build_object('type', 'array', 'items', jsonb_build_object('type', 'string', 'enum', v_values), 'uniqueItems', true)
      || jsonb_strip_nulls(jsonb_build_object('minItems', coalesce(field -> 'min', v_floor), 'maxItems', field -> 'max'))
    when 'nps' then '{"type": "integer", "minimum": 0, "maximum": ${String(NPS_MAX)}}'::jsonb
    else '{}'::jsonb
  end;
  return v_out || jsonb_strip_nulls(jsonb_build_object('title', field -> 'label', 'description', field -> 'help'));
end;
$$;
revoke execute on function ${fn("form_field_schema")}(jsonb) from public, anon, authenticated;

-- The schema a showIf condition holds under, as an if.
create or replace function ${fn("form_condition_schema")}(condition jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'properties', jsonb_build_object(condition ->> 'field',
      case
        when condition ? 'equals' then jsonb_build_object('const', condition -> 'equals')
        when condition ? 'in' then jsonb_build_object('enum', condition -> 'in')
        else '{"not": {"enum": [null, "", []]}}'::jsonb
      end),
    'required', jsonb_build_array(condition ->> 'field'))
$$;
revoke execute on function ${fn("form_condition_schema")}(jsonb) from public, anon, authenticated;

-- The JSON Schema 2020-12 a version's answers validate against. Mirrors
-- formSchema in core/contracts/form-definition.ts: a required field with a
-- showIf (its own or its step's) is required only while the condition holds.
create or replace function ${fn("form_schema")}(definition jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_properties jsonb := '{}'::jsonb;
  v_required jsonb := '[]'::jsonb;
  v_conditional jsonb := '[]'::jsonb;
  v_conditions jsonb;
  v_step jsonb;
  v_field jsonb;
begin
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      v_properties := v_properties || jsonb_build_object(v_field ->> 'key', ${fn("form_field_schema")}(v_field));
      continue when coalesce((v_field ->> 'required')::boolean, false) is false;
      v_conditions := '[]'::jsonb;
      if v_step ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array(${fn("form_condition_schema")}(v_step -> 'showIf'));
      end if;
      if v_field ? 'showIf' then
        v_conditions := v_conditions || jsonb_build_array(${fn("form_condition_schema")}(v_field -> 'showIf'));
      end if;
      if jsonb_array_length(v_conditions) = 0 then
        v_required := v_required || jsonb_build_array(v_field ->> 'key');
      else
        v_conditional := v_conditional || jsonb_build_array(jsonb_build_object(
          'if', case when jsonb_array_length(v_conditions) = 1 then v_conditions -> 0 else jsonb_build_object('allOf', v_conditions) end,
          'then', jsonb_build_object('required', jsonb_build_array(v_field ->> 'key'))));
      end if;
    end loop;
  end loop;
  return jsonb_build_object('$schema', ${sqlString(FORM_SCHEMA_DIALECT)}, 'type', 'object', 'properties', v_properties, 'additionalProperties', false)
    || case when jsonb_array_length(v_required) > 0 then jsonb_build_object('required', v_required) else '{}'::jsonb end
    || case when jsonb_array_length(v_conditional) > 0 then jsonb_build_object('allOf', v_conditional) else '{}'::jsonb end;
end;
$$;
revoke execute on function ${fn("form_schema")}(jsonb) from public, anon, authenticated;

-- Checks a definition (its shape, then what the shape can't say, as
-- formDefinitionProblems does) and copies each customField's definition in.
create or replace function ${fn("form_resolve")}(tenant ${ctx.idType}, definition jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_errors text[];
  v_problem text;
  v_steps jsonb := '[]'::jsonb;
  v_fields jsonb;
  v_step jsonb;
  v_field jsonb;
  v_custom jsonb;
  v_options jsonb;
  v_step_keys text[] := '{}';
  v_keys text[] := '{}';
  v_scored boolean := false;
begin
  v_errors := extensions.jsonschema_validation_errors(${sqlString(JSON.stringify(FORM_DEFINITION_SCHEMA))}::json, definition::json);
  if cardinality(v_errors) > 0 then
    ${definitionInvalid("v_errors")}
  end if;
  <<steps>>
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    if (v_step ->> 'key') = any (v_step_keys) then
      v_problem := format('step %s is listed twice', v_step ->> 'key');
      exit;
    end if;
    v_step_keys := v_step_keys || (v_step ->> 'key');
    if v_step ? 'showIf' and not ((v_step -> 'showIf' ->> 'field') = any (v_keys)) then
      v_problem := format('step %s: showIf names %s, which isn''t an earlier field', v_step ->> 'key', v_step -> 'showIf' ->> 'field');
      exit;
    end if;
    v_fields := '[]'::jsonb;
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      if (v_field ->> 'key') = any (v_keys) then
        v_problem := format('field %s is listed twice', v_field ->> 'key');
        exit steps;
      end if;
      if v_field ? 'showIf' and not ((v_field -> 'showIf' ->> 'field') = any (v_keys)) then
        v_problem := format('field %s: showIf names %s, which isn''t an earlier field', v_field ->> 'key', v_field -> 'showIf' ->> 'field');
        exit steps;
      end if;
      v_keys := v_keys || (v_field ->> 'key');
      v_custom := null;
      ${customFieldResolve(ctx).replaceAll("exit;", "exit steps;")}
      if not (v_field ? 'label' and v_field ? 'type') then
        v_problem := format('field %s needs a label and a type, or a customField', v_field ->> 'key');
        exit steps;
      end if;
      if (v_field ->> 'type') in ('option', 'multi') and coalesce(jsonb_array_length(v_field -> 'options'), 0) = 0 then
        v_problem := format('field %s needs options', v_field ->> 'key');
        exit steps;
      end if;
      if v_field ? 'pattern' then
        begin
          perform '' ~ (v_field ->> 'pattern');
        exception when invalid_regular_expression then
          v_problem := format('field %s: pattern is not a valid regular expression', v_field ->> 'key');
        end;
        exit steps when v_problem is not null;
      end if;
      if v_field ? 'correct' then
        v_scored := true;
        if v_field -> 'correct' = 'null'::jsonb then
          v_problem := format('field %s: correct can''t be null', v_field ->> 'key');
          exit steps;
        end if;
        if (v_field ->> 'type') in (${UNSCORED_FIELD_TYPES.map(sqlString).join(", ")}) then
          v_problem := format('field %s: a %s field can''t have a correct answer', v_field ->> 'key', v_field ->> 'type');
          exit steps;
        end if;
        if not ${fn("form_correct_fits")}(v_field) then
          v_problem := format('field %s: correct isn''t an answer the field takes', v_field ->> 'key');
          exit steps;
        end if;
      elsif v_field ? 'points' then
        v_problem := format('field %s: points need a correct answer', v_field ->> 'key');
        exit steps;
      end if;
      v_fields := v_fields || jsonb_build_array(v_field);
    end loop;
    v_steps := v_steps || jsonb_build_array(jsonb_set(v_step, '{fields}', v_fields));
  end loop;
  if v_problem is null and definition ? 'scoring' and not v_scored then
    v_problem := 'scoring needs a field with a correct answer';
  end if;
  if v_problem is not null then
    v_errors := array[v_problem];
    ${definitionInvalid("v_errors")}
  end if;
  return jsonb_build_object('steps', v_steps)
    || case when definition ? 'scoring' then jsonb_build_object('scoring', definition -> 'scoring') else '{}'::jsonb end;
end;
$$;
revoke execute on function ${fn("form_resolve")}(${ctx.idType}, jsonb) from public, anon, authenticated;
`;
}

/**
 * The SQL twins of the scoring in `blocks/forms/scoring.ts` and the correct
 * answer check in `formDefinitionProblems`. `form_score` grades answers against
 * a version's answer key, so the client never sends a score.
 */
export function formScoringFunctions(ctx: ModuleContext): string {
  const fn = (name: string): string => ctx.fn(name);

  return `-- Whether a field's correct answer is one it takes. Mirrors correctFits in
-- core/contracts/form-definition.ts.
create or replace function ${fn("form_correct_fits")}(field jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case field ->> 'type'
    when 'text' then jsonb_typeof(field -> 'correct') = 'string'
    when 'textarea' then jsonb_typeof(field -> 'correct') = 'string'
    when 'email' then jsonb_typeof(field -> 'correct') = 'string'
    when 'url' then jsonb_typeof(field -> 'correct') = 'string'
    when 'date' then jsonb_typeof(field -> 'correct') = 'string'
    when 'number' then jsonb_typeof(field -> 'correct') = 'number'
    when 'integer' then case when jsonb_typeof(field -> 'correct') = 'number'
      then (field ->> 'correct')::numeric = trunc((field ->> 'correct')::numeric) else false end
    when 'bool' then jsonb_typeof(field -> 'correct') = 'boolean'
    when 'option' then jsonb_typeof(field -> 'correct') = 'string'
      and exists (select 1 from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) o where o -> 'value' = field -> 'correct')
    when 'multi' then jsonb_typeof(field -> 'correct') = 'array'
      and jsonb_array_length(field -> 'correct') > 0
      and not exists (
        select 1 from jsonb_array_elements(field -> 'correct') v
        where jsonb_typeof(v) <> 'string'
          or not exists (select 1 from jsonb_array_elements(coalesce(field -> 'options', '[]'::jsonb)) o where o -> 'value' = v))
    else false
  end
$$;
revoke execute on function ${fn("form_correct_fits")}(jsonb) from public, anon, authenticated;

-- Whether a showIf condition holds for the answers. Mirrors conditionHolds in
-- blocks/forms/questionnaire.ts.
create or replace function ${fn("form_condition_holds")}(condition jsonb, answers jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when not answers ? (condition ->> 'field') then false
    when condition ? 'equals' then answers -> (condition ->> 'field') = condition -> 'equals'
    when condition ? 'in' then exists (select 1 from jsonb_array_elements(condition -> 'in') x where x = answers -> (condition ->> 'field'))
    else not (answers -> (condition ->> 'field') in ('null'::jsonb, '""'::jsonb, '[]'::jsonb))
  end
$$;
revoke execute on function ${fn("form_condition_holds")}(jsonb, jsonb) from public, anon, authenticated;

-- Whether an answer earns a field's points: text without case and surrounding
-- spaces, a multi answer as a set, anything else as the same JSON value.
create or replace function ${fn("form_answer_matches")}(type text, answer jsonb, correct jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when type in ('text', 'textarea', 'email', 'url') then jsonb_typeof(answer) = 'string' and jsonb_typeof(correct) = 'string'
      and lower(btrim(answer #>> '{}', ' ')) = lower(btrim(correct #>> '{}', ' '))
    when type = 'multi' then jsonb_typeof(answer) = 'array' and jsonb_typeof(correct) = 'array'
      and answer @> correct and correct @> answer
    else coalesce(answer = correct, false)
  end
$$;
revoke execute on function ${fn("form_answer_matches")}(text, jsonb, jsonb) from public, anon, authenticated;

-- A submission's grade: { score, maxScore, passed } against the answer key
-- (field key to correct answer), or null for a form without one. A field its
-- showIf (or its step's) hides counts toward neither score; passed is null
-- without scoring.passMark. Mirrors formScore in blocks/forms/scoring.ts.
create or replace function ${fn("form_score")}(definition jsonb, answer_key jsonb, answers jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_step jsonb;
  v_field jsonb;
  v_points numeric;
  v_score numeric := 0;
  v_max numeric := 0;
  v_pass numeric := (definition -> 'scoring' ->> 'passMark')::numeric;
begin
  if answer_key is null or answer_key = '{}'::jsonb then
    return null;
  end if;
  for v_step in select x from jsonb_array_elements(definition -> 'steps') x loop
    continue when v_step ? 'showIf' and not ${fn("form_condition_holds")}(v_step -> 'showIf', answers);
    for v_field in select x from jsonb_array_elements(v_step -> 'fields') x loop
      continue when not answer_key ? (v_field ->> 'key');
      continue when v_field ? 'showIf' and not ${fn("form_condition_holds")}(v_field -> 'showIf', answers);
      v_points := coalesce((v_field ->> 'points')::numeric, 1);
      v_max := v_max + v_points;
      if answers ? (v_field ->> 'key')
        and ${fn("form_answer_matches")}(v_field ->> 'type', answers -> (v_field ->> 'key'), answer_key -> (v_field ->> 'key')) then
        v_score := v_score + v_points;
      end if;
    end loop;
  end loop;
  return jsonb_build_object('score', v_score, 'maxScore', v_max,
    'passed', case when v_pass is null then null else v_score * 100 >= v_pass * v_max end);
end;
$$;
revoke execute on function ${fn("form_score")}(jsonb, jsonb, jsonb) from public, anon, authenticated;

-- The definition without its correct answers, and the answer key they make
-- (field key to correct answer), as { definition, key }.
create or replace function ${fn("form_answer_split")}(definition jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'definition', jsonb_set(definition, '{steps}', coalesce((
      select jsonb_agg(jsonb_set(s.step, '{fields}', (
        select jsonb_agg(f.field - 'correct' order by f.ord)
        from jsonb_array_elements(s.step -> 'fields') with ordinality as f(field, ord))) order by s.ord)
      from jsonb_array_elements(definition -> 'steps') with ordinality as s(step, ord)), '[]'::jsonb)),
    'key', coalesce((
      select jsonb_object_agg(f.field ->> 'key', f.field -> 'correct')
      from jsonb_array_elements(definition -> 'steps') s(step)
      cross join lateral jsonb_array_elements(s.step -> 'fields') f(field)
      where f.field ? 'correct'), '{}'::jsonb))
$$;
revoke execute on function ${fn("form_answer_split")}(jsonb) from public, anon, authenticated;

-- A stored definition with its answer key put back, for the form's managers.
create or replace function ${fn("form_answer_merge")}(definition jsonb, answer_key jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when answer_key is null or answer_key = '{}'::jsonb then definition
  else jsonb_set(definition, '{steps}', coalesce((
    select jsonb_agg(jsonb_set(s.step, '{fields}', (
      select jsonb_agg(case when answer_key ? (f.field ->> 'key') then f.field || jsonb_build_object('correct', answer_key -> (f.field ->> 'key')) else f.field end order by f.ord)
      from jsonb_array_elements(s.step -> 'fields') with ordinality as f(field, ord))) order by s.ord)
    from jsonb_array_elements(definition -> 'steps') with ordinality as s(step, ord)), '[]'::jsonb))
  end
$$;
revoke execute on function ${fn("form_answer_merge")}(jsonb, jsonb) from public, anon, authenticated;
`;
}
