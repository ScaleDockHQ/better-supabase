SET local check_function_bodies = off;

DROP INDEX "better_supabase"."field_values_definition_idx";

ALTER TABLE "better_supabase"."field_values"
  DROP CONSTRAINT "field_values_tenant_id_subject_type_subject_id_definition_i_key";

DROP FUNCTION "api"."read_field_values"(uuid, text, text);

DROP FUNCTION "api"."set_field_value"(uuid, text, text, uuid, text);

DROP FUNCTION "better_supabase"."read_field_values"(uuid, text, text);

DROP FUNCTION "better_supabase"."set_field_value"(uuid, text, text, uuid, text);

ALTER TABLE "better_supabase"."field_values"
  ADD COLUMN "legal_entity_id" uuid;

CREATE OR REPLACE FUNCTION api.import_field_value (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."import_field_value"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.install_field_pack (
  tenant uuid,
  pack   jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."install_field_pack"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.read_field_values (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."read_field_values"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.set_field_value (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  definition   uuid,
  value        text,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."set_field_value"($1, $2, $3, $4, $5, $6) $function$;

CREATE OR REPLACE FUNCTION better_supabase.import_apply_batch (
  run    uuid,
  entity text,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_run_id uuid := import_apply_batch.run;
  v_entity text := import_apply_batch.entity;
  v_items jsonb := import_apply_batch.items;
  v_run "better_supabase"."import_runs";
  v_item jsonb;
  v_call jsonb;
  v_key text;
  v_scope text;
  v_data jsonb;
  v_hash text;
  v_rec "better_supabase"."import_records";
  v_other text;
  v_found boolean;
  v_done boolean;
  v_subject_id text;
  v_subject_type text;
  v_current timestamptz;
  v_out jsonb;
  v_subjects jsonb;
  v_subject jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
  v_conflicted integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_message text;
  v_hint text;
begin
  select * into v_run from "better_supabase"."import_runs" r where r."id" = v_run_id;
  if v_entity <> all (array['data_lifecycle_row', 'field_value', 'supplier_item', 'product_identifier', 'customer']::text[]) then
    raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
  end if;
  if jsonb_typeof(v_items) <> 'array' then
    raise exception 'items must be an array of { key, scope, data, refs }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  for v_item in select e.value from jsonb_array_elements(v_items) e loop
    v_key := v_item ->> 'key';
    v_scope := coalesce(v_item ->> 'scope', '');
    v_data := v_item -> 'data';

    if v_key is null or v_key = '' or jsonb_typeof(v_data) is distinct from 'object' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', 'IMPORT_ITEM_INVALID', 'message', 'an item needs a key and a data object'));
      continue;
    end if;

    -- jsonb text is key-ordered, so equal content hashes equally.
    v_hash := encode(extensions.digest(v_data::text, 'sha256'), 'hex');

    begin
      v_done := false;
      select * into v_rec from "better_supabase"."import_records" x
      where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_scope
        and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary';
      v_found := found;

      if not v_found then
        -- A cloned administration reuses the subjects of the scope it aliases
        -- when the content is equal there.
        for v_other in
          select a."of" from jsonb_to_recordset(v_run."scope_aliases") as a(scope text, "of" text, entities jsonb)
          where a.scope = v_scope
            and (a.entities is null or jsonb_typeof(a.entities) <> 'array' or jsonb_array_length(a.entities) = 0 or a.entities ? v_entity)
        loop
          if exists (
            select 1 from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key and x."role" = 'primary' and x."content_hash" = v_hash
          ) then
            insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import")
            select x."tenant_id", x."source", v_scope, x."entity", x."external_key", x."role", x."subject_type", x."subject_id", x."content_hash", v_run_id, v_run_id, x."subject_updated_at_at_import"
            from "better_supabase"."import_records" x
            where x."tenant_id" = v_run."tenant_id" and x."source" = v_run."source" and x."scope" = v_other
              and x."entity" = v_entity and x."external_key" = v_key
            on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do nothing;
            v_unchanged := v_unchanged + 1;
            v_done := true;
            exit;
          end if;
        end loop;
      elsif v_rec."content_hash" = v_hash then
        update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
        where x."tenant_id" = v_rec."tenant_id" and x."source" = v_rec."source" and x."scope" = v_rec."scope"
          and x."entity" = v_rec."entity" and x."external_key" = v_rec."external_key"
          and (x."last_run_id" is distinct from v_run_id or x."missing_since" is not null);
        v_unchanged := v_unchanged + 1;
        v_done := true;
      else
        -- A row a user changed after the last import stays as it is.
        v_current := null;
        case v_entity
        when 'supplier_item' then
          v_current := "better_supabase"."supplier_item_updated_at"(v_rec."subject_id");
        when 'product_identifier' then
          v_current := "better_supabase"."product_identifier_updated_at"(v_rec."subject_id");
        when 'customer' then
          v_current := "public"."import_customer_updated_at"(v_rec."subject_id");
          else null;
        end case;
        if v_current is not null and v_rec."subject_updated_at_at_import" is not null and v_current > v_rec."subject_updated_at_at_import" then
          update "better_supabase"."import_records" x set "last_run_id" = v_run_id, "missing_since" = null
          where x."id" = v_rec."id";
          v_conflicted := v_conflicted + 1;
          v_done := true;
        end if;
      end if;

      if not v_done then
        v_subject_id := case when v_found then v_rec."subject_id" else null end;
        v_call := v_item || jsonb_build_object('tenant', v_run."tenant_id", 'scope', v_scope);
        case v_entity
      when 'data_lifecycle_row' then
        v_subject_type := 'data_lifecycle_row';
        v_out := "better_supabase"."restore_data_row"(v_run_id, v_call, v_subject_id);
      when 'field_value' then
        v_subject_type := 'field_value';
        v_out := "better_supabase"."import_field_value"(v_run_id, v_call, v_subject_id);
      when 'supplier_item' then
        v_subject_type := 'supplier_item';
        v_out := "better_supabase"."import_supplier_item"(v_run_id, v_call, v_subject_id);
      when 'product_identifier' then
        v_subject_type := 'product_identifier';
        v_out := "better_supabase"."import_product_identifier"(v_run_id, v_call, v_subject_id);
      when 'customer' then
        v_subject_type := 'customer';
        v_out := "public"."import_customer"(v_run_id, v_call, v_subject_id);
      else
        raise exception 'no import target for this entity' using errcode = '22023', hint = 'IMPORT_TARGET_UNKNOWN';
    end case;

        v_subjects := case jsonb_typeof(v_out) when 'array' then v_out else jsonb_build_array(v_out) end;
        if not exists (
          select 1 from jsonb_array_elements(v_subjects) s
          where coalesce(s.value ->> 'role', 'primary') = 'primary' and nullif(s.value ->> 'subjectId', '') is not null
        ) then
          raise exception 'the import target returned no primary subject' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
        end if;

        for v_subject in select s.value from jsonb_array_elements(v_subjects) s loop
          insert into "better_supabase"."import_records" ("tenant_id", "source", "scope", "entity", "external_key", "role", "subject_type", "subject_id", "content_hash", "first_run_id", "last_run_id", "subject_updated_at_at_import", "missing_since")
          values (
            v_run."tenant_id", v_run."source", v_scope, v_entity, v_key,
            coalesce(v_subject ->> 'role', 'primary'),
            coalesce(v_subject ->> 'subjectType', v_subject_type),
            v_subject ->> 'subjectId',
            v_hash, v_run_id, v_run_id,
            coalesce((v_subject ->> 'updatedAt')::timestamptz, now()),
            null
          )
          on conflict ("tenant_id", "source", "scope", "entity", "external_key", "role") do update set
            "subject_type" = excluded."subject_type",
            "subject_id" = excluded."subject_id",
            "content_hash" = excluded."content_hash",
            "last_run_id" = excluded."last_run_id",
            "subject_updated_at_at_import" = excluded."subject_updated_at_at_import",
            "missing_since" = null;
        end loop;

        if v_found then
          v_updated := v_updated + 1;
        else
          v_inserted := v_inserted + 1;
        end if;
      end if;
    exception when others then
      get stacked diagnostics v_message = message_text, v_hint = pg_exception_hint;
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('entity', v_entity, 'key', v_key, 'code', coalesce(nullif(v_hint, ''), 'IMPORT_ITEM_INVALID'), 'message', v_message));
    end;
  end loop;

  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated, 'unchanged', v_unchanged, 'conflicted', v_conflicted, 'errors', v_errors);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_field_value (
  run        uuid,
  item       jsonb,
  subject_id text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid := (import_field_value.item ->> 'tenant')::uuid;
  v_scope text := coalesce(import_field_value.item ->> 'scope', '');
  v_data jsonb := import_field_value.item -> 'data';
  v_reference jsonb := v_data -> 'subject';
  v_type text := nullif(v_data ->> 'subjectType', '');
  v_subject text := nullif(v_data ->> 'subjectId', '');
  v_field text := v_data ->> 'field';
  v_value text;
  v_definition uuid;
  v_field_type text;
  v_entity uuid;
  v_row uuid;
begin
  if jsonb_typeof(v_data -> 'value') in ('object', 'array', 'null') or (v_data -> 'value') is null then
    raise exception 'a field value needs a value of text, a number or a boolean' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_value := v_data ->> 'value';
  if v_field is null or v_field = '' then
    raise exception 'a field value needs the key of its field' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_entity := nullif(v_data ->> 'legalEntityId', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'legalEntityId must be a uuid' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_reference is not null then
    if jsonb_typeof(v_reference) is distinct from 'object' then
      raise exception 'subject is { entity, key }' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select x."subject_type", x."subject_id" into v_type, v_subject
    from "better_supabase"."import_records" x
    join "better_supabase"."import_runs" u on u."id" = import_field_value.run
    where x."tenant_id" = v_tenant and x."source" = u."source"
      and x."scope" = v_scope
      and x."entity" = v_reference ->> 'entity' and x."external_key" = v_reference ->> 'key'
      and x."role" = 'primary';
    if not found then
      raise exception 'the record isn''t in the import record map; import it first' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
  end if;
  if v_type is null or v_subject is null then
    raise exception 'a field value needs a subject: { entity, key }, or subjectType and subjectId' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_type is null or v_type <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'invoice', 'ledger_account', 'product', 'product_variant', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'content_entry', 'document', 'customer', 'drive_node', 'application', 'change_request', 'project', 'task']::text[]) then
    raise exception 'the entity is not a registered subject type' using errcode = '22023', hint = 'FIELD_ENTITY_UNKNOWN';
  end if;
  select d."id", d."type" into v_definition, v_field_type
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = v_tenant and d."entity" = v_type and d."key" = v_field;
  if not found then
    raise exception 'no field definition with this key on the subject type' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if not (case v_field_type when 'bsn' then "better_supabase"."bsb_valid_bsn"(v_value) when 'iban' then "better_supabase"."bsb_valid_iban"(v_value) when 'phone_e164' then v_value ~* '^\+[1-9][0-9]{1,14}$' else true end) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  select y."id" into v_row from "better_supabase"."field_values" y
  where y."tenant_id" = v_tenant and y."subject_type" = v_type and y."subject_id" = v_subject and y."definition_id" = v_definition
    and coalesce(y.legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(v_entity, '00000000-0000-0000-0000-000000000000'::uuid);
  if found then
    update "better_supabase"."field_values" set "value_text" = case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, v_value) else v_value end where "id" = v_row;
  else
    insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text", legal_entity_id)
    values (v_tenant, v_definition, v_type, v_subject, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = v_definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || v_tenant::text, v_value) else v_value end, v_entity)
    returning "id" into v_row;
  end if;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', v_tenant, 'id', v_row, 'subjectType', v_type, 'subjectId', v_subject), 'field-values/' || v_row::text, (v_tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('subjectId', v_row::text, 'subjectType', 'field_value');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.install_field_pack (
  tenant uuid,
  pack   jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_key text := install_field_pack.pack ->> 'key';
  v_version integer;
  v_entity text;
  v_fields jsonb;
  v_field jsonb;
  v_field_key text;
  v_label text;
  v_type text;
  v_required boolean;
  v_sensitive boolean;
  v_permission text;
  v_row record;
  v_id uuid;
  v_last text;
  v_rank text;
  v_created integer := 0;
  v_updated integer := 0;
  v_unchanged integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', install_field_pack.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    raise exception 'a field pack is an object with apiVersion 1' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if v_key is null or v_key !~ '^[a-z][a-z0-9_.-]{0,62}$' then
    raise exception 'a field pack needs a key in lower case' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    raise exception 'a field pack needs a version of 1 or more' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    raise exception 'a field pack needs subjects: { <type>: fields }' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    if v_entity is null or v_entity <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'invoice', 'ledger_account', 'product', 'product_variant', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'content_entry', 'document', 'customer', 'drive_node', 'application', 'change_request', 'project', 'task']::text[]) then
    raise exception 'the entity is not a registered subject type' using errcode = '22023', hint = 'FIELD_ENTITY_UNKNOWN';
  end if;
    if jsonb_typeof(v_fields) is distinct from 'array' then
      raise exception 'the fields of a subject type are a list' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        raise exception 'a field is an object of key, label and type' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ '^[a-z][a-z0-9_.-]{0,62}$' or v_label is null or btrim(v_label) = '' then
        raise exception 'a field needs a key in lower case and a label' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if v_type is null or v_type not in ('text', 'number', 'date', 'bool', 'option', 'json', 'email', 'url', 'multi_option', 'user', 'rating', 'currency', 'bsn', 'iban', 'phone_e164') then
        raise exception 'a field needs one of the custom field types' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        raise exception 'required and sensitive are booleans' using errcode = '22023', hint = 'FIELD_PACK_INVALID';
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, false);

      select d."id" as id, d."pack" as pack, d."pack_version" as version, d."label" as label, d."type" as type,
        d."required" as required, d."sensitive" as sensitive, d."permission" as permission
      into v_row
      from "better_supabase"."field_definitions" d
      where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity and d."key" = v_field_key;

      if not found then
        select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
        where d."tenant_id" = install_field_pack.tenant and d."entity" = v_entity;
        v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
        insert into "better_supabase"."field_definitions" ("tenant_id", "entity", "key", "label", "type", "required", "sensitive", "permission", "pack", "pack_version", "rank")
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version, v_rank)
        returning "id" into v_id;
        v_created := v_created + 1;
        perform "better_supabase".emit_event('field_definition.created', jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_id, 'entity', v_entity), 'custom-fields/' || v_id::text, (install_field_pack.tenant)::text, null, 'better-supabase/custom-fields');
      elsif v_row.pack is distinct from v_key then
        raise exception 'the field already exists and doesn''t belong to this pack' using errcode = '23505', hint = 'FIELD_PACK_CONFLICT';
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update "better_supabase"."field_definitions" set "label" = v_label, "type" = v_type, "required" = v_required, "sensitive" = v_sensitive,
          "permission" = v_permission, "pack_version" = v_version
        where "id" = v_row.id;
        v_updated := v_updated + 1;
        perform "better_supabase".emit_event('field_definition.updated', jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_row.id, 'entity', v_entity), 'custom-fields/' || v_row.id::text, (install_field_pack.tenant)::text, null, 'better-supabase/custom-fields');
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_field_definitions (
  tenant uuid,
  entity text
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
    'rank', d."rank"
  ) order by d."rank" collate "C", d."key"), '[]'::jsonb)
  from "better_supabase"."field_definitions" d
  where d."tenant_id" = list_field_definitions.tenant
    and d."entity" = list_field_definitions.entity
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', list_field_definitions.tenant, 'custom_fields.read'), false))
$function$;

CREATE OR REPLACE FUNCTION better_supabase.read_field_values (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  legal_entity uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_values jsonb;
  v_key text;
  v_read jsonb;
begin
  v_key := "better_supabase"."field_key"('tenant:' || read_field_values.tenant::text, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', case when coalesce(d."encrypted", false) then "better_supabase"."field_open"(v_key, v."value_text") else v."value_text" end)), '[]'::jsonb),
    jsonb_agg(v."id") filter (where coalesce(d."encrypted", false) or coalesce(d."sensitive", false))
  into v_values, v_read
  from (select distinct on (x."definition_id") x.* from "better_supabase"."field_values" x
    where x."tenant_id" = read_field_values.tenant
      and x."subject_type" = read_field_values.subject_type
      and x."subject_id" = read_field_values.subject_id
      and (x.legal_entity_id is null or x.legal_entity_id = read_field_values.legal_entity)
    order by x."definition_id", x.legal_entity_id nulls last) v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or (case when read_field_values.subject_type in ('drive_node') then case read_field_values.subject_type
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (read_field_values.subject_id)::uuid and s."tenant_id" = read_field_values.tenant and (coalesce(better_supabase.can('tenant', read_field_values.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end else coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false) end))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.read_sensitive')), false));
  if v_read is not null then
    perform better_supabase.audit_event(
    event_type => 'field_value.viewed',
    category => 'read',
    target_type => 'field_value',
    record_id => read_field_values.subject_id,
    summary => 'Read ' || jsonb_array_length(v_read)::text || ' protected field value(s) of ' || read_field_values.subject_type,
    tenant => (read_field_values.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', read_field_values.tenant, 'subjectType', read_field_values.subject_type, 'subjectId', read_field_values.subject_id, 'ids', v_read)
  );
  end if;
  if jsonb_array_length(v_values) > 0 then
    perform "better_supabase"."record_subject_read"(read_field_values.subject_type, read_field_values.subject_id, null, 'custom-fields', 'read_field_values');
  end if;
  return v_values;
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
    raise exception 'not allowed to manage custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if save_field_definition.entity is null or save_field_definition.entity <> all (array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'invoice', 'ledger_account', 'product', 'product_variant', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'content_entry', 'document', 'customer', 'drive_node', 'application', 'change_request', 'project', 'task']::text[]) then
    raise exception 'the entity is not a registered subject type' using errcode = '22023', hint = 'FIELD_ENTITY_UNKNOWN';
  end if;
  select max(d."rank" collate "C") into v_last from "better_supabase"."field_definitions" d
    where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
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
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$function$;

ALTER TABLE "better_supabase"."field_values"
  ADD CONSTRAINT "bsb_field_values_legal_entity_fk" FOREIGN KEY (tenant_id, legal_entity_id) REFERENCES better_supabase.legal_entities(tenant_id, id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX bsb_field_values_entity_key_idx ON better_supabase.field_values
  USING btree (tenant_id, subject_type, subject_id, definition_id, COALESCE(legal_entity_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX bsb_field_values_legal_entity_idx ON better_supabase.field_values USING btree (tenant_id, legal_entity_id)
  WHERE (legal_entity_id IS NOT NULL);

REVOKE ALL ON FUNCTION "api"."import_field_value"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."import_field_value"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."install_field_pack"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."install_field_pack"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."read_field_values"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."read_field_values"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."set_field_value"(uuid, text, text, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."set_field_value"(uuid, text, text, uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."import_field_value"(uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."import_field_value"(uuid, jsonb, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."install_field_pack"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."install_field_pack"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."read_field_values"(uuid, text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."read_field_values"(uuid, text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_field_value"(uuid, text, text, uuid, text, uuid) TO "authenticated", "service_role";
