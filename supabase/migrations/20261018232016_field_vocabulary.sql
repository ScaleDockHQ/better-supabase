SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."field_definitions"
  DROP CONSTRAINT "field_definitions_type_check";

CREATE OR REPLACE FUNCTION better_supabase.form_resolve (
  tenant     uuid,
  definition jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
begin
  v_errors := extensions.jsonschema_validation_errors('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["steps"],"additionalProperties":false,"properties":{"steps":{"type":"array","minItems":1,"maxItems":50,"items":{"type":"object","required":["key","fields"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"title":{"type":"string","maxLength":200},"description":{"type":"string","maxLength":2000},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"fields":{"type":"array","minItems":1,"maxItems":200,"items":{"type":"object","required":["key"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"label":{"type":"string","minLength":1,"maxLength":200},"type":{"enum":["text","textarea","email","url","number","integer","date","bool","consent","option","multi","json"]},"required":{"type":"boolean"},"help":{"type":"string","maxLength":1000},"placeholder":{"type":"string","maxLength":200},"options":{"type":"array","minItems":1,"maxItems":500,"items":{"type":"object","required":["value","label"],"additionalProperties":false,"properties":{"value":{"type":"string","minLength":1,"maxLength":200},"label":{"type":"string","minLength":1,"maxLength":200}}}},"min":{"type":"number"},"max":{"type":"number"},"minLength":{"type":"integer","minimum":0},"maxLength":{"type":"integer","minimum":1},"pattern":{"type":"string","maxLength":500},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"customField":{"type":"string","pattern":"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"}}}}}}}}}'::json, definition::json);
  if cardinality(v_errors) > 0 then
    raise exception 'the form definition is invalid: %', array_to_string(v_errors, '; ')
      using errcode = '22023', detail = to_jsonb(v_errors)::text, hint = 'FORM_DEFINITION_INVALID';
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
      if v_field ? 'customField' then
        select jsonb_strip_nulls(jsonb_build_object('label', d."label", 'type', case d."type" when 'multi_option' then 'multi' when 'user' then 'text' when 'rating' then 'integer' when 'currency' then 'integer' else d."type" end, 'required', d."required"))
            || case when d."type" = 'rating' then jsonb_build_object('min', 1, 'max', 5) else '{}'::jsonb end
          into v_custom
          from "better_supabase"."field_definitions" d
          where d."id" = (v_field ->> 'customField')::uuid and d."tenant_id" = form_resolve.tenant;
        if v_custom is null then
          v_problem := format('field %s: customField %s is not a field definition in this organization', v_field ->> 'key', v_field ->> 'customField');
        exit steps;
        end if;
        if v_custom ->> 'type' in ('option', 'multi') and not v_field ? 'options' and to_regclass('"better_supabase"."field_options"') is not null then
          execute format('select jsonb_agg(jsonb_build_object(''value'', o."value", ''label'', o."label") order by o."value") from %s o where o."definition_id" = $1', to_regclass('"better_supabase"."field_options"'))
            into v_options using (v_field ->> 'customField')::uuid;
          v_custom := v_custom || jsonb_strip_nulls(jsonb_build_object('options', v_options));
        end if;
        v_field := v_custom || v_field;
      end if;
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
      v_fields := v_fields || jsonb_build_array(v_field);
    end loop;
    v_steps := v_steps || jsonb_build_array(jsonb_set(v_step, '{fields}', v_fields));
  end loop;
  if v_problem is not null then
    v_errors := array[v_problem];
    raise exception 'the form definition is invalid: %', array_to_string(v_errors, '; ')
      using errcode = '22023', detail = to_jsonb(v_errors)::text, hint = 'FORM_DEFINITION_INVALID';
  end if;
  return jsonb_build_object('steps', v_steps);
end;
$function$;

ALTER TABLE "better_supabase"."field_definitions"
  ADD CONSTRAINT "bs_field_definitions_type"
    CHECK
    ((type = ANY (ARRAY['text'::text, 'number'::text, 'date'::text, 'bool'::text, 'option'::text, 'json'::text, 'email'::text, 'url'::text, 'multi_option'::text, 'user'::text,
    'rating'::text, 'currency'::text])));

COMMENT ON CONSTRAINT "bs_field_definitions_type" ON "better_supabase"."field_definitions" IS 'better-supabase check 41e34c72';
