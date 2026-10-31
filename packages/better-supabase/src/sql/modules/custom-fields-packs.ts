import type { BlockSqlContext } from "../context.ts";
import type { ImportTargetContribution } from "../contributions.ts";

import { CUSTOM_FIELD_TYPES } from "../../core/contracts/field-formats.ts";
import { sqlString } from "../../core/template.ts";
import { customFieldValueCheck } from "../format-checks.ts";
import { rankAfter } from "../rank-sql.ts";
import { fail, serviceGrant, userGrant } from "../shared.ts";
import { fieldSubjects } from "./custom-fields-keyed.ts";

/** The pack key and the field key patterns, also checked by `defineFieldPack`. */
const FIELD_PACK_KEY_PATTERN = "^[a-z][a-z0-9_.-]{0,62}$";

/** The name of the entity `import_upsert_batch` takes for field values. */
const FIELD_VALUE_IMPORT_ENTITY = "field_value";

const zeroUuid = "'00000000-0000-0000-0000-000000000000'::uuid";

/**
 * The subject types field definitions can name: `blocks.custom-fields.on`, else
 * `config.subjects` with the entities of the installed blocks. Empty when the
 * app registers none, and then an entity stays free text.
 */
function registeredEntities(ctx: BlockSqlContext): readonly string[] {
  return fieldSubjects(ctx).map(([type]) => type);
}

/**
 * The statement that raises `FIELD_ENTITY_UNKNOWN` unless the text expression
 * `entity` is a registered subject type. Empty without registered types.
 */
export function entityCheck(ctx: BlockSqlContext, entity: string): string {
  const types = registeredEntities(ctx);

  if (types.length === 0) {
    return "";
  }

  return `if ${entity} is null or ${entity} <> all (array[${types.map((type) => sqlString(type)).join(", ")}]::text[]) then
    ${fail("FIELD_ENTITY_UNKNOWN", "the entity is not a registered subject type", "22023")}
  end if;`;
}

/**
 * Whether values can belong to one legal entity: the normalized layout, an own
 * values table that names its definition, and a managed `legal-entities` block,
 * which adds the nullable `legal_entity_id` column.
 */
export function perEntityValues(ctx: BlockSqlContext): boolean {
  return (
    ctx.text("layout", "normalized") === "normalized" &&
    ctx.manages &&
    ctx.has("values", "definition") &&
    ctx.installed("legal-entities") &&
    ctx.of("legal-entities").mode === "managed"
  );
}

/** Whether the definitions carry the pack they came from. */
export function packsOn(ctx: BlockSqlContext): boolean {
  return (
    ctx.text("layout", "normalized") === "normalized" &&
    ctx.has("definitions", "pack") &&
    ctx.has("definitions", "packVersion")
  );
}

/** The column the entity values add to `field_values`, as the block names it. */
export const FIELD_VALUE_ENTITY_COLUMN = "legal_entity_id";

const TYPES = CUSTOM_FIELD_TYPES.map((type) => sqlString(type)).join(", ");

/**
 * `install_field_pack(tenant, pack)`: installs or updates the definitions of a
 * field pack in one organization. A definition is identified by its pack and
 * key; installing the same pack again changes nothing, a higher version updates
 * the label, type and flags, and a definition of another pack or one created by
 * hand is never overwritten.
 */
export function installFieldPack(ctx: BlockSqlContext, manage: string): string {
  const definitions = ctx.table("definitions");
  const d = (logical: string): string => ctx.col("definitions", logical);
  const ranked = ctx.has("definitions", "rank");
  const rank = ranked ? d("rank") : "";
  const sensitiveDefault = "false";

  return `
-- Installs a field pack (apiVersion 1): { key, version, subjects: { <type>:
-- [{ key, label, type, required?, sensitive?, permission? }] } }. A definition
-- is matched by (pack, key), so a second install changes nothing.
create or replace function ${ctx.fn("install_field_pack")}(tenant ${ctx.idType}, pack jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  if not (auth.role() = 'service_role' or ${ctx.scope.can("install_field_pack.tenant", manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to manage custom fields")}
  end if;
  if jsonb_typeof(install_field_pack.pack) is distinct from 'object' or install_field_pack.pack ->> 'apiVersion' is distinct from '1' then
    ${fail("FIELD_PACK_INVALID", "a field pack is an object with apiVersion 1", "22023")}
  end if;
  if v_key is null or v_key !~ ${sqlString(FIELD_PACK_KEY_PATTERN)} then
    ${fail("FIELD_PACK_INVALID", "a field pack needs a key in lower case", "22023")}
  end if;
  begin
    v_version := (install_field_pack.pack ->> 'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_version := null;
  end;
  if v_version is null or v_version < 1 then
    ${fail("FIELD_PACK_INVALID", "a field pack needs a version of 1 or more", "22023")}
  end if;
  if jsonb_typeof(install_field_pack.pack -> 'subjects') is distinct from 'object' then
    ${fail("FIELD_PACK_INVALID", "a field pack needs subjects: { <type>: fields }", "22023")}
  end if;

  for v_entity, v_fields in select s.key, s.value from jsonb_each(install_field_pack.pack -> 'subjects') s order by s.key loop
    ${entityCheck(ctx, "v_entity")}
    if jsonb_typeof(v_fields) is distinct from 'array' then
      ${fail("FIELD_PACK_INVALID", "the fields of a subject type are a list", "22023")}
    end if;
    for v_field in select f.value from jsonb_array_elements(v_fields) f loop
      if jsonb_typeof(v_field) is distinct from 'object' then
        ${fail("FIELD_PACK_INVALID", "a field is an object of key, label and type", "22023")}
      end if;
      v_field_key := v_field ->> 'key';
      v_label := v_field ->> 'label';
      v_type := v_field ->> 'type';
      v_permission := nullif(v_field ->> 'permission', '');
      if v_field_key is null or v_field_key !~ ${sqlString(FIELD_PACK_KEY_PATTERN)} or v_label is null or btrim(v_label) = '' then
        ${fail("FIELD_PACK_INVALID", "a field needs a key in lower case and a label", "22023")}
      end if;
      if v_type is null or v_type not in (${TYPES}) then
        ${fail("FIELD_PACK_INVALID", "a field needs one of the custom field types", "22023")}
      end if;
      if (v_field ? 'required' and jsonb_typeof(v_field -> 'required') <> 'boolean') or (v_field ? 'sensitive' and jsonb_typeof(v_field -> 'sensitive') <> 'boolean') then
        ${fail("FIELD_PACK_INVALID", "required and sensitive are booleans", "22023")}
      end if;
      v_required := coalesce((v_field ->> 'required')::boolean, false);
      v_sensitive := coalesce((v_field ->> 'sensitive')::boolean, ${sensitiveDefault});

      select d.${d("id")} as id, d.${d("pack")} as pack, d.${d("packVersion")} as version, d.${d("label")} as label, d.${d("type")} as type,
        d.${d("required")} as required, d.${d("sensitive")} as sensitive, d.${d("permission")} as permission
      into v_row
      from ${definitions} d
      where d.${d("tenant")} = install_field_pack.tenant and d.${d("entity")} = v_entity and d.${d("key")} = v_field_key;

      if not found then
        ${
          ranked
            ? `select max(d.${rank} collate "C") into v_last from ${definitions} d
        where d.${d("tenant")} = install_field_pack.tenant and d.${d("entity")} = v_entity;
        v_rank := ${rankAfter("v_last")};
        `
            : ""
        }insert into ${definitions} (${d("tenant")}, ${d("entity")}, ${d("key")}, ${d("label")}, ${d("type")}, ${d("required")}, ${d("sensitive")}, ${d("permission")}, ${d("pack")}, ${d("packVersion")}${ranked ? `, ${rank}` : ""})
        values (install_field_pack.tenant, v_entity, v_field_key, v_label, v_type, v_required, v_sensitive, v_permission, v_key, v_version${ranked ? ", v_rank" : ""})
        returning ${d("id")} into v_id;
        v_created := v_created + 1;
        ${ctx.record({
          type: "field_definition.created",
          payload: `jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_id, 'entity', v_entity)`,
          subject: `'custom-fields/' || v_id::text`,
          tenant: "install_field_pack.tenant",
          audit: false,
        })}
      elsif v_row.pack is distinct from v_key then
        ${fail("FIELD_PACK_CONFLICT", "the field already exists and doesn't belong to this pack", "23505")}
      elsif v_row.label = v_label and v_row.type = v_type and v_row.required = v_required and v_row.sensitive = v_sensitive
        and v_row.permission is not distinct from v_permission and v_row.version is not distinct from v_version then
        v_unchanged := v_unchanged + 1;
      else
        update ${definitions} set ${d("label")} = v_label, ${d("type")} = v_type, ${d("required")} = v_required, ${d("sensitive")} = v_sensitive,
          ${d("permission")} = v_permission, ${d("packVersion")} = v_version
        where ${d("id")} = v_row.id;
        v_updated := v_updated + 1;
        ${ctx.record({
          type: "field_definition.updated",
          payload: `jsonb_build_object('organizationId', install_field_pack.tenant, 'id', v_row.id, 'entity', v_entity)`,
          subject: `'custom-fields/' || v_row.id::text`,
          tenant: "install_field_pack.tenant",
          audit: false,
        })}
      end if;
    end loop;
  end loop;
  return jsonb_build_object('pack', v_key, 'version', v_version, 'created', v_created, 'updated', v_updated, 'unchanged', v_unchanged);
end;
$$;
${userGrant(`${ctx.fn("install_field_pack")}(${ctx.idType}, jsonb)`)}
`;
}

/** What the import target of field values needs from the module's own parts. */
export interface FieldValueImportParts {
  /**
   * The expression that encrypts `value` for definition `v_definition`, or
   * `value`.
   */
  readonly seal: (value: string) => string;
  /** The `field_value.set` record statement for `v_row`. */
  readonly record: string;
}

/** Whether the module renders `import_field_value`. */
export function importsOn(ctx: BlockSqlContext): boolean {
  return (
    ctx.text("layout", "normalized") === "normalized" &&
    ctx.manages &&
    ctx.has("values", "definition") &&
    ctx.installed("imports") &&
    ctx.of("imports").mode !== "custom"
  );
}

/** What `contributes.imports` returns: the `field_value` target. */
export function fieldValueImportTargets(
  own: BlockSqlContext,
): readonly ImportTargetContribution[] {
  if (!importsOn(own)) {
    return [];
  }

  return [
    {
      entity: FIELD_VALUE_IMPORT_ENTITY,
      subjectType: FIELD_VALUE_IMPORT_ENTITY,
      write: own.fn("import_field_value").replaceAll('"', ""),
    },
  ];
}

/**
 * `import_field_value(run, item, subject_id)`: the import target of the
 * `field_value` entity. `item.data` is `{ field, value, subject, legalEntityId?
 * }` where `subject` is `{ entity, key }`, the external key of the record the
 * value belongs to in the same import source, or `subjectType` and `subjectId`
 * name the record directly. The item's own key identifies the value.
 */
export function importFieldValue(
  ctx: BlockSqlContext,
  parts: FieldValueImportParts,
): string {
  const definitions = ctx.table("definitions");
  const values = ctx.table("values");
  const d = (logical: string): string => ctx.col("definitions", logical);
  const v = (logical: string): string => ctx.col("values", logical);
  const imports = ctx.of("imports");
  const records = imports.table("records");
  const runs = imports.table("runs");
  const x = (column: string): string => imports.col("records", column);
  const r = (column: string): string => imports.col("runs", column);
  const entityOn = perEntityValues(ctx);
  const entityColumn = FIELD_VALUE_ENTITY_COLUMN;

  return `
-- The import target of the field_value entity (ADR 0156). A subject is named by
-- its external key in the run's source, so the value follows the record the
-- import record map holds.
create or replace function ${ctx.fn("import_field_value")}(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant ${ctx.idType} := (import_field_value.item ->> 'tenant')::${ctx.idType};
  v_scope text := coalesce(import_field_value.item ->> 'scope', '');
  v_data jsonb := import_field_value.item -> 'data';
  v_reference jsonb := v_data -> 'subject';
  v_type text := nullif(v_data ->> 'subjectType', '');
  v_subject text := nullif(v_data ->> 'subjectId', '');
  v_field text := v_data ->> 'field';
  v_value text;
  v_definition uuid;
  v_field_type text;${entityOn ? `\n  v_entity uuid;` : ""}
  v_row uuid;
begin
  if jsonb_typeof(v_data -> 'value') in ('object', 'array', 'null') or (v_data -> 'value') is null then
    ${fail("IMPORT_ITEM_INVALID", "a field value needs a value of text, a number or a boolean", "22023")}
  end if;
  v_value := v_data ->> 'value';
  if v_field is null or v_field = '' then
    ${fail("IMPORT_ITEM_INVALID", "a field value needs the key of its field", "22023")}
  end if;
  begin${entityOn ? `\n    v_entity := nullif(v_data ->> 'legalEntityId', '')::uuid;` : ""}
  exception when invalid_text_representation then
    ${fail("IMPORT_ITEM_INVALID", "legalEntityId must be a uuid", "22023")}
  end;${
    entityOn
      ? ""
      : `
  if v_data ? 'legalEntityId' then
    ${fail("IMPORT_ITEM_INVALID", "values per legal entity need the legal-entities block", "22023")}
  end if;`
  }
  if v_reference is not null then
    if jsonb_typeof(v_reference) is distinct from 'object' then
      ${fail("IMPORT_ITEM_INVALID", "subject is { entity, key }", "22023")}
    end if;
    select x.${x("subjectType")}, x.${x("subjectId")} into v_type, v_subject
    from ${records} x
    join ${runs} u on u.${r("id")} = import_field_value.run
    where x.${x("tenant")} = v_tenant and x.${x("source")} = u.${r("source")}
      and x.${x("scope")} = v_scope
      and x.${x("entity")} = v_reference ->> 'entity' and x.${x("externalKey")} = v_reference ->> 'key'
      and x.${x("role")} = 'primary';
    if not found then
      ${fail("IMPORT_ITEM_INVALID", "the record isn't in the import record map; import it first", "22023")}
    end if;
  end if;
  if v_type is null or v_subject is null then
    ${fail("IMPORT_ITEM_INVALID", "a field value needs a subject: { entity, key }, or subjectType and subjectId", "22023")}
  end if;
  ${entityCheck(ctx, "v_type")}
  select d.${d("id")}, d.${d("type")} into v_definition, v_field_type
  from ${definitions} d
  where d.${d("tenant")} = v_tenant and d.${d("entity")} = v_type and d.${d("key")} = v_field;
  if not found then
    ${fail("IMPORT_ITEM_INVALID", "no field definition with this key on the subject type", "22023")}
  end if;
  if not (${customFieldValueCheck("v_field_type", "v_value", ctx.schemaName)}) then
    ${fail("IMPORT_ITEM_INVALID", "the value doesn't match the field's format", "22023")}
  end if;

  select y.${v("id")} into v_row from ${values} y
  where y.${v("tenant")} = v_tenant and y.${v("subjectType")} = v_type and y.${v("subjectId")} = v_subject and y.${v("definition")} = v_definition${
    entityOn
      ? `
    and coalesce(y.${entityColumn}, ${zeroUuid}) = coalesce(v_entity, ${zeroUuid})`
      : ""
  };
  if found then
    update ${values} set ${v("valueText")} = ${parts.seal("v_value")} where ${v("id")} = v_row;
  else
    insert into ${values} (${v("tenant")}, ${v("definition")}, ${v("subjectType")}, ${v("subjectId")}, ${v("valueText")}${entityOn ? `, ${entityColumn}` : ""})
    values (v_tenant, v_definition, v_type, v_subject, ${parts.seal("v_value")}${entityOn ? ", v_entity" : ""})
    returning ${v("id")} into v_row;
  end if;
  ${parts.record}
  return jsonb_build_object('subjectId', v_row::text, 'subjectType', ${sqlString(FIELD_VALUE_IMPORT_ENTITY)});
end;
$$;
${serviceGrant(`${ctx.fn("import_field_value")}(uuid, jsonb, text)`)}
`;
}
