SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.delete_field_value (
  value_id uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_field_value"($1) $function$;

CREATE OR REPLACE FUNCTION api.update_field_value (
  value_id uuid,
  value    text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_field_value"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_field_value (
  value_id uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_subject text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."tenant_id", v."subject_type", v."subject_id"
  into v_tenant, v_type, v_subject
  from "better_supabase"."field_values" v where v."id" = delete_field_value.value_id;
  if not found then
    raise exception 'field value not found' using errcode = 'P0002', hint = 'FIELD_VALUE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to delete this field value' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if not (case v_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(v_type, v_subject, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to delete fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_values" where "id" = delete_field_value.value_id;
  perform "better_supabase".emit_event('field_value.deleted', jsonb_build_object('organizationId', v_tenant, 'id', delete_field_value.value_id, 'subjectType', v_type, 'subjectId', v_subject), 'field-values/' || delete_field_value.value_id::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_field_value (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  definition   uuid,
  value        text,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if not (case set_field_value.subject_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(set_field_value.subject_type, set_field_value.subject_id, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to set fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text", legal_entity_id)
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end, set_field_value.legal_entity)
  on conflict ("tenant_id", "subject_type", "subject_id", "definition_id", (coalesce(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid)))
  do update set "value_text" = excluded."value_text"
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_field_value (
  value_id uuid,
  value    text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_type text;
  v_subject text;
  v_definition uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select v."tenant_id", v."subject_type", v."subject_id", v."definition_id"
  into v_tenant, v_type, v_subject, v_definition
  from "better_supabase"."field_values" v where v."id" = update_field_value.value_id;
  if not found then
    raise exception 'field value not found' using errcode = 'P0002', hint = 'FIELD_VALUE_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if not (case v_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(v_type, v_subject, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to set fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(update_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(update_field_value.value) when 'phone_e164' then update_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  update "better_supabase"."field_values" set "value_text" = case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, update_field_value.value) else update_field_value.value end
  where "id" = update_field_value.value_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', v_tenant, 'id', update_field_value.value_id, 'subjectType', v_type, 'subjectId', v_subject), 'field-values/' || update_field_value.value_id::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', update_field_value.value_id);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."delete_field_value"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_field_value"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_field_value"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_field_value"(uuid, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_field_value"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_field_value"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_field_value"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_field_value"(uuid, text) TO "authenticated", "service_role";
