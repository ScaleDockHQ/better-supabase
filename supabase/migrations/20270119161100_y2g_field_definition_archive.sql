SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_field_definition"(uuid);

DROP FUNCTION "api"."list_field_definitions"(uuid, text);

DROP FUNCTION "better_supabase"."delete_field_definition"(uuid);

DROP FUNCTION "better_supabase"."list_field_definitions"(uuid, text);

ALTER TABLE "better_supabase"."field_definitions"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_field_definition (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_field_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_field_definitions (
  tenant           uuid,
  entity           text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_field_definitions"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.purge_field_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_field_definition"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_field_definition (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_field_definition"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_field_definition (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_archived timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "archived_at" into v_tenant, v_archived from "better_supabase"."field_definitions" where "id" = archive_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if (v_archived is not null) = true then
    return jsonb_build_object('id', archive_field_definition.definition, 'archivedAt', v_archived);
  end if;
  update "better_supabase"."field_definitions" set "archived_at" = now() where "id" = archive_field_definition.definition
  returning "archived_at" into v_archived;
  perform "better_supabase".emit_event('field_definition.archived', jsonb_build_object('organizationId', v_tenant, 'id', archive_field_definition.definition), 'custom-fields/' || archive_field_definition.definition::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', archive_field_definition.definition, 'archivedAt', v_archived);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_field_definitions (
  tenant           uuid,
  entity           text,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d."id",
    'entity', d."entity",
    'key', d."key",
    'label', d."label",
    'type', d."type",
    'required', d."required",
    'sensitive', d."sensitive",
    'encrypted', d."encrypted",
    'pack', d."pack",
    'packVersion', d."pack_version",
    'archivedAt', d."archived_at",
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (coalesce(list_field_definitions.include_archived, false) or d."archived_at" is null)
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_field_definition (
  definition uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."field_definitions" where "id" = purge_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to purge custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  delete from "better_supabase"."field_definitions" where "id" = purge_field_definition.definition;
  perform "better_supabase".emit_event('field_definition.purged', jsonb_build_object('organizationId', v_tenant, 'id', purge_field_definition.definition), 'custom-fields/' || purge_field_definition.definition::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_field_definition (
  definition uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_archived timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id", "archived_at" into v_tenant, v_archived from "better_supabase"."field_definitions" where "id" = restore_field_definition.definition;
  if not found then
    raise exception 'field not found' using errcode = 'P0002', hint = 'CUSTOM_FIELD_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if (v_archived is not null) = false then
    return jsonb_build_object('id', restore_field_definition.definition, 'archivedAt', v_archived);
  end if;
  update "better_supabase"."field_definitions" set "archived_at" = null where "id" = restore_field_definition.definition
  returning "archived_at" into v_archived;
  perform "better_supabase".emit_event('field_definition.restored', jsonb_build_object('organizationId', v_tenant, 'id', restore_field_definition.definition), 'custom-fields/' || restore_field_definition.definition::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', restore_field_definition.definition, 'archivedAt', v_archived);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_field_definition (
  tenant    uuid,
  entity    text,
  key       text,
  label     text,
  type      text,
  sensitive boolean
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_id uuid;
  v_inserted boolean;
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if save_field_definition.entity is null or save_field_definition.entity <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'ledger_account', 'invoice', 'product', 'product_variant', 'rfq', 'till', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'warranty_claim', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'maintenance_plan', 'dam_usage_right', 'lims_sample', 'tax_code', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'advisory', 'advisory_product', 'vulnerability', 'content_entry', 'document', 'customer', 'drive_node', 'organization', 'application', 'change_request', 'project', 'task']::text[]) then
    raise exception 'the entity is not a registered subject type' using errcode = '22023', hint = 'CUSTOM_FIELD_ENTITY_UNKNOWN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  if exists (select 1 from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity
      and d."key" = save_field_definition.key and d."archived_at" is not null) then
    raise exception 'field is archived; restore it first' using errcode = '55000', hint = 'CUSTOM_FIELD_ARCHIVED';
  end if;
  insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "sensitive", "rank")
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false), v_rank)
  on conflict ("tenant_id", "entity", "key")
  do update set "label" = excluded."label", "sensitive" = excluded."sensitive"
  returning "id", xmax = 0 into v_id, v_inserted;
  if v_inserted then
    perform "better_supabase".emit_event('field_definition.created', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  else
    perform "better_supabase".emit_event('field_definition.updated', jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity), 'custom-fields/' || coalesce(v_id::text, save_field_definition.key), (save_field_definition.tenant)::text, null, 'better-supabase/custom-fields');
  end if;
  return jsonb_build_object('id', v_id);
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
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'CUSTOM_FIELD_FORBIDDEN';
  end if;
  if not (case set_field_value.subject_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(set_field_value.subject_type, set_field_value.subject_id, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to set fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."archived_at" is not null) then
    raise exception 'field is archived; restore it first' using errcode = '55000', hint = 'CUSTOM_FIELD_ARCHIVED';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'CUSTOM_FIELD_VALUE_INVALID';
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

REVOKE ALL ON FUNCTION "api"."archive_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_field_definitions"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_field_definitions"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_field_definitions"(uuid, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_field_definitions"(uuid, text, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_field_definition"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_field_definition"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_field_definition"(uuid) TO "authenticated", "service_role";
