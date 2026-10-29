SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."field_definitions"
  DROP CONSTRAINT "bsb_field_definitions_type";

CREATE OR REPLACE FUNCTION api.bsb_valid_bsn (
  value text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."bsb_valid_bsn"($1) $function$;

CREATE OR REPLACE FUNCTION api.bsb_valid_iban (
  value text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."bsb_valid_iban"($1) $function$;

CREATE OR REPLACE FUNCTION api.field_lookup (
  owner text,
  value text
)
  RETURNS bytea
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."field_lookup"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_valid_bsn (
  value text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  STRICT
  SET search_path TO ''
  AS $function$
  select case
    when value !~ '^[0-9]{9}$' or value = '000000000' then false
    else (
      select sum(substr(value, i, 1)::integer * case when i = 9 then -1 else 10 - i end)
      from generate_series(1, 9) as i
    ) % 11 = 0
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_valid_iban (
  value text
)
  RETURNS boolean
  LANGUAGE sql
  IMMUTABLE
  PARALLEL SAFE
  STRICT
  SET search_path TO ''
  AS $function$
  select case
    when value !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$' then false
    else (
      select string_agg(case when ascii(c.ch) between 65 and 90 then (ascii(c.ch) - 55)::text else c.ch end, '' order by c.n)
      from regexp_split_to_table(substr(value, 5) || substr(value, 1, 4), '') with ordinality as c(ch, n)
    )::numeric % 97 = 1
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drop_field_key (
  owner text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'only the service role drops field keys' using errcode = '42501', hint = 'FIELD_KEY_FORBIDDEN';
  end if;
  delete from vault.secrets s where s.name in ('bs:field-key:' || drop_field_key.owner, 'bs:field-lookup-key:' || drop_field_key.owner);
  if not found then
    return false;
  end if;
  perform "better_supabase".emit_event('field_key.dropped', jsonb_build_object('owner', drop_field_key.owner), 'field-keys/' || drop_field_key.owner, null, null, 'better-supabase/field-encryption');
  perform better_supabase.audit_event(
    event_type => 'field_key.dropped',
    category => 'security',
    target_type => 'field_key',
    record_id => drop_field_key.owner,
    metadata => jsonb_build_object('owner', drop_field_key.owner)
  );
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.encrypt_field_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_key text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "type" into v_tenant, v_type from "better_supabase"."field_definitions" where "id" = encrypt_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if v_type not in ('text', 'email', 'url', 'bsn', 'iban', 'phone_e164') then
    raise exception 'only text fields can be encrypted' using errcode = '22023', hint = 'FIELD_NOT_ENCRYPTABLE';
  end if;
  v_key := "better_supabase"."field_key"('tenant:' || v_tenant::text, true);
  update "better_supabase"."field_definitions" set "encrypted" = true where "id" = encrypt_field_definition.definition;
  update "better_supabase"."field_values" set "value_text" = "better_supabase"."field_seal"(v_key, "value_text")
  where "definition_id" = encrypt_field_definition.definition
    and "value_text" is not null
    and left("value_text", 5) <> 'bsf1:';
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_hash (
  key   text,
  value text
)
  RETURNS bytea
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select case when field_hash.key is null or field_hash.value is null then null
    else extensions.hmac(convert_to(lower(regexp_replace(field_hash.value, '\s', '', 'g')), 'UTF8'), decode(field_hash.key, 'base64'), 'sha256')
  end
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_lookup (
  owner text,
  value text
)
  RETURNS bytea
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if field_lookup.value is null then
    return null;
  end if;
  return "better_supabase"."field_hash"("better_supabase"."field_lookup_key"(field_lookup.owner, false), field_lookup.value);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_lookup_key (
  owner text,
  make  boolean DEFAULT true
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_key text;
begin
  if field_lookup_key.owner is null or length(field_lookup_key.owner) = 0 then
    raise exception 'a field key needs an owner' using errcode = '22023', hint = 'FIELD_KEY_OWNER';
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is not null or not field_lookup_key.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('bs:field-lookup-key:' || field_lookup_key.owner, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = 'bs:field-lookup-key:' || field_lookup_key.owner;
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, 'bs:field-lookup-key:' || field_lookup_key.owner, 'better-supabase field lookup key');
  end if;
  return v_key;
end;
$function$;

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
  v_scored boolean := false;
begin
  v_errors := extensions.jsonschema_validation_errors('{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","required":["steps"],"additionalProperties":false,"properties":{"steps":{"type":"array","minItems":1,"maxItems":50,"items":{"type":"object","required":["key","fields"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"title":{"type":"string","maxLength":200},"description":{"type":"string","maxLength":2000},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"fields":{"type":"array","minItems":1,"maxItems":200,"items":{"type":"object","required":["key"],"additionalProperties":false,"properties":{"key":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"label":{"type":"string","minLength":1,"maxLength":200},"type":{"enum":["text","textarea","email","url","number","integer","date","bool","consent","option","multi","json","nps"]},"required":{"type":"boolean"},"help":{"type":"string","maxLength":1000},"placeholder":{"type":"string","maxLength":200},"options":{"type":"array","minItems":1,"maxItems":500,"items":{"type":"object","required":["value","label"],"additionalProperties":false,"properties":{"value":{"type":"string","minLength":1,"maxLength":200},"label":{"type":"string","minLength":1,"maxLength":200}}}},"min":{"type":"number"},"max":{"type":"number"},"minLength":{"type":"integer","minimum":0},"maxLength":{"type":"integer","minimum":1},"pattern":{"type":"string","maxLength":500},"showIf":{"type":"object","required":["field"],"minProperties":2,"maxProperties":2,"additionalProperties":false,"properties":{"field":{"type":"string","pattern":"^[a-z][a-zA-Z0-9_]{0,62}$"},"equals":{},"in":{"type":"array","minItems":1,"maxItems":500},"filled":{"const":true}}},"customField":{"type":"string","pattern":"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"},"correct":{},"points":{"type":"number","minimum":0,"maximum":10000}}}}}}},"scoring":{"type":"object","additionalProperties":false,"properties":{"passMark":{"type":"number","minimum":0,"maximum":100}}}}}'::json, definition::json);
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
        select jsonb_strip_nulls(jsonb_build_object('label', d."label", 'type', case d."type" when 'multi_option' then 'multi' when 'user' then 'text' when 'rating' then 'integer' when 'currency' then 'integer' when 'bsn' then 'text' when 'iban' then 'text' when 'phone_e164' then 'text' else d."type" end, 'required', d."required"))
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
      if v_field ? 'correct' then
        v_scored := true;
        if v_field -> 'correct' = 'null'::jsonb then
          v_problem := format('field %s: correct can''t be null', v_field ->> 'key');
          exit steps;
        end if;
        if (v_field ->> 'type') in ('consent', 'json', 'nps') then
          v_problem := format('field %s: a %s field can''t have a correct answer', v_field ->> 'key', v_field ->> 'type');
          exit steps;
        end if;
        if not "better_supabase"."form_correct_fits"(v_field) then
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
    raise exception 'the form definition is invalid: %', array_to_string(v_errors, '; ')
      using errcode = '22023', detail = to_jsonb(v_errors)::text, hint = 'FORM_DEFINITION_INVALID';
  end if;
  return jsonb_build_object('steps', v_steps)
    || case when definition ? 'scoring' then jsonb_build_object('scoring', definition -> 'scoring') else '{}'::jsonb end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_field_value (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  definition   uuid,
  value        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end)
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$function$;

ALTER TABLE "better_supabase"."field_definitions"
  ADD CONSTRAINT "bsb_field_definitions_type"
    CHECK
    ((type = ANY (ARRAY['text'::text, 'number'::text, 'date'::text, 'bool'::text, 'option'::text, 'json'::text, 'email'::text, 'url'::text, 'multi_option'::text, 'user'::text,
    'rating'::text, 'currency'::text, 'bsn'::text, 'iban'::text, 'phone_e164'::text])));

COMMENT ON CONSTRAINT "bsb_field_definitions_type" ON "better_supabase"."field_definitions" IS 'better-supabase check 068e6990';

REVOKE ALL ON FUNCTION "api"."bsb_valid_bsn"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."bsb_valid_bsn"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."bsb_valid_iban"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."bsb_valid_iban"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."field_lookup"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."field_lookup"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bsb_valid_bsn"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."bsb_valid_bsn"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bsb_valid_iban"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."bsb_valid_iban"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."field_hash"(text, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."field_lookup"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."field_lookup"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."field_lookup_key"(text, boolean) FROM PUBLIC;
