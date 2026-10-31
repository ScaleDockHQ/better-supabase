import type { CustomFieldsEvents } from "../../blocks/custom-fields/events.ts";
import type { CustomFieldType } from "../../core/contracts/field-formats.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { CUSTOM_FIELD_TYPES } from "../../core/contracts/field-formats.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { createdOrUpdated } from "../event-verbs.ts";
import {
  CUSTOM_FIELD_VALIDATORS,
  customFieldValueCheck,
  formatValidatorSql,
} from "../format-checks.ts";
import { RANK_KEY_PATTERN, rankAfter, rankBackfill } from "../rank-sql.ts";
import {
  ensureCheck,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { subjectActionCheck, subjectReadable } from "../subjects.ts";
import {
  checkSubjectColumns,
  fieldReadGate,
  fieldSubjects,
  keyedContract,
  keyedFields,
  keyedOptions,
  recordReadSubjects,
} from "./custom-fields-keyed.ts";
import {
  FIELD_VALUE_ENTITY_COLUMN,
  entityCheck,
  fieldValueImportTargets,
  importFieldValue,
  importsOn,
  installFieldPack,
  packsOn,
  perEntityValues,
} from "./custom-fields-packs.ts";
import { FIELD_CIPHER_PREFIX } from "./field-encryption.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The custom field types whose values `encrypt_field_definition` encrypts. */
const ENCRYPTABLE_TYPES: readonly CustomFieldType[] = [
  "text",
  "email",
  "url",
  "bsn",
  "iban",
  "phone_e164",
];

const EVENTS: BlockSqlEvents<CustomFieldsEvents> = {
  "field_definition.created": {
    subject: "custom-fields",
    payload: ["organizationId", "id", "entity"],
  },
  "field_definition.updated": {
    subject: "custom-fields",
    payload: ["organizationId", "id", "entity"],
  },
  "field_definition.deleted": {
    subject: "custom-fields",
    payload: ["organizationId", "id"],
  },
  "field_value.set": {
    subject: "field-values",
    payload: ["organizationId", "id", "subjectType", "subjectId"],
  },
  "field_value.deleted": {
    subject: "field-values",
    payload: ["organizationId", "id", "subjectType", "subjectId"],
  },
  "field_value.viewed": {
    subject: "field-values",
    payload: ["organizationId", "subjectType", "subjectId", "ids"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    field_definition: {
      table: "definitions",
      singular: "field_definition",
      formerly: "field",
      primary: true,
    },
  },
  events: EVENTS,
  options: [
    "layout",
    "auditReads",
    "rankType",
    "readAccess",
    "packs",
    "entityMap",
  ],
  tables: {
    definitions: {
      name: "field_definitions",
      app: { unused: () => ["encrypted"] },
      optionalTable: true,
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        entity: "entity",
        key: "key",
        label: "label",
        type: "type",
        required: "required",
        sensitive: "sensitive",
        permission: "permission",
        rank: "rank",
        encrypted: "encrypted",
        pack: "pack",
        packVersion: "pack_version",
      },
      optional: ["rank", "encrypted", "pack", "packVersion"],
    },
    options: {
      name: "field_options",
      app: {},
      optionalTable: true,
      columns: {
        id: "id",
        definition: "definition_id",
        value: "value",
        label: "label",
        rank: "rank",
      },
      optional: ["rank"],
    },
    values: {
      name: "field_values",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        definition: "definition_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        valueText: "value_text",
        valueNumber: "value_number",
        valueDate: "value_date",
        valueBool: "value_bool",
        optionId: "option_id",
        valueJson: "value_json",
        valueUrl: "value_url",
        valueEmail: "value_email",
        key: "key",
        label: "label",
        type: "type",
        rank: "rank",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "definition",
        "valueJson",
        "subjectType",
        "subjectId",
        "optionId",
        "valueUrl",
        "valueEmail",
        "key",
        "label",
        "type",
        "rank",
        "createdAt",
        "updatedAt",
      ],
      typed: ["type", "subjectType"],
    },
  },
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const layout = ctx.text("layout", "normalized");
  const inline = layout === "inline";

  if (layout !== "inline" && layout !== "normalized" && layout !== "keyed") {
    throw new TypeError(
      'blocks.custom-fields.options.layout must be "normalized", "inline" or "keyed"',
    );
  }

  const manageKey = ctx.permission(
    "manage",
    OPERATIONS["custom-fields.manage"],
  );

  const { rankType, readAccess } = keyedOptions(ctx);

  if (layout === "keyed") {
    return `${schemaPreamble(ctx)}
${formatValidatorSql(ctx.schemaName, CUSTOM_FIELD_VALIDATORS)}
${keyedFields(
  ctx,
  {
    manage: manageKey,
    read: ctx.permission("read", OPERATIONS["custom-fields.read"]),
  },
  { rankType, readAccess },
)}`;
  }

  if (rankType !== "text") {
    throw new TypeError(
      'blocks.custom-fields.options.rankType applies only to layout "keyed"',
    );
  }

  checkSubjectColumns(ctx, false);

  const subjects = fieldSubjects(ctx);
  const recordSubjects = recordReadSubjects(subjects, readAccess);

  const keyed = subjects.find(
    ([, subject]) => subject.extra["keys"] !== undefined,
  );

  if (keyed !== undefined) {
    throw new TypeError(
      `blocks.custom-fields.on.${keyed[0]}.keys applies only to layout "keyed"`,
    );
  }

  if (readAccess === "record" && subjects.length === 0) {
    throw new TypeError(
      'blocks.custom-fields.options.readAccess "record" needs record types in config.subjects or blocks.custom-fields.on',
    );
  }

  const subjectWrite = subjectActionCheck(
    ctx,
    subjects,
    { type: "set_field_value.subject_type", id: "set_field_value.subject_id" },
    ["fields"],
  );

  const definitions = ctx.table("definitions");
  const ranked = !inline && ctx.has("definitions", "rank");
  const rank = ranked ? ctx.col("definitions", "rank") : "";
  const values = ctx.table("values");
  const manage = manageKey;
  const read = ctx.permission("read", OPERATIONS["custom-fields.read"]);

  const sensitive = ctx.permission(
    "sensitive",
    OPERATIONS["custom-fields.sensitive"],
  );

  const encryption = encrypts(ctx) ? ctx.of("field-encryption") : undefined;

  const encrypted =
    encryption === undefined
      ? ""
      : `coalesce(d.${ctx.col("definitions", "encrypted")}, false)`;

  const audited = ctx.flag("auditReads", false);

  const logRead = ctx.read(
    "read_field_values.subject_type",
    "read_field_values.subject_id",
    "read_field_values",
  );

  if (audited && !ctx.installed("audit")) {
    throw new TypeError(
      "blocks.custom-fields.options.auditReads needs the audit block; add it to blocks",
    );
  }

  const tables = ctx.manages
    ? `${
        inline
          ? ""
          : `create table if not exists ${definitions} (
  ${ctx.col("definitions", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("definitions", "tenant")} ${ctx.idType} not null,
  ${ctx.col("definitions", "entity")} text not null,
  ${ctx.col("definitions", "key")} text not null,
  ${ctx.col("definitions", "label")} text not null,
  ${ctx.col("definitions", "type")} text not null,
  ${ctx.col("definitions", "required")} boolean not null default false,
  ${ctx.col("definitions", "sensitive")} boolean not null default false,
  ${ctx.col("definitions", "permission")} text,
${ctx.has("definitions", "encrypted") ? `  ${ctx.col("definitions", "encrypted")} boolean not null default false,\n` : ""}${packsOn(ctx) ? `  ${ctx.col("definitions", "pack")} text,\n  ${ctx.col("definitions", "packVersion")} integer,\n` : ""}${ranked ? `  ${rank} text collate "C" not null default 'V',\n` : ""}  unique (${ctx.col("definitions", "tenant")}, ${ctx.col("definitions", "entity")}, ${ctx.col("definitions", "key")})
);
${typeCheck(ctx, definitions)}
${lockTable(definitions, { read: true })}
`
      }create table if not exists ${values} (
  ${ctx.col("values", "id")} uuid primary key default gen_random_uuid(),
  ${ctx.col("values", "tenant")} ${ctx.idType} not null,
  ${inline || !ctx.has("values", "definition") ? "" : `${ctx.col("values", "definition")} uuid references ${definitions} (${ctx.col("definitions", "id")}) on delete cascade,`}
  ${ctx.col("values", "subjectType")} text not null,
  ${ctx.col("values", "subjectId")} text not null,
  ${ctx.col("values", "valueText")} text,
  ${ctx.col("values", "valueNumber")} numeric,
  ${ctx.col("values", "valueDate")} date,
  ${ctx.col("values", "valueBool")} boolean,
  ${ctx.col("values", "optionId")} uuid${ctx.has("values", "valueJson") ? `,` : ""}
  ${ctx.has("values", "valueJson") ? `${ctx.col("values", "valueJson")} jsonb` : ""}
  ${inline || !ctx.has("values", "definition") || perEntityValues(ctx) ? "" : `, unique (${ctx.col("values", "tenant")}, ${ctx.col("values", "subjectType")}, ${ctx.col("values", "subjectId")}, ${ctx.col("values", "definition")})`}
);
${lockTable(values, { read: true })}
${inline || !ctx.has("values", "definition") || perEntityValues(ctx) ? "" : `create index if not exists ${ctx.naming.rename("field_values_definition_idx")} on ${values} (${ctx.col("values", "definition")});`}
`
    : !inline && ctx.has("definitions", "encrypted")
      ? `alter table ${definitions} add column if not exists ${ctx.col("definitions", "encrypted")} boolean not null default false;
${packColumns(ctx, definitions)}`
      : inline
        ? ""
        : packColumns(ctx, definitions);

  const perEntity = perEntityValues(ctx);

  // The organization's values, or with a legal entity the entity's value where
  // it has one and the organization's value where it doesn't.
  const readableValues = perEntity
    ? `(select distinct on (x.${ctx.col("values", "definition")}) x.* from ${values} x
    where x.${ctx.col("values", "tenant")} = read_field_values.tenant
      and x.${ctx.col("values", "subjectType")} = read_field_values.subject_type
      and x.${ctx.col("values", "subjectId")} = read_field_values.subject_id
      and (x.${FIELD_VALUE_ENTITY_COLUMN} is null or x.${FIELD_VALUE_ENTITY_COLUMN} = read_field_values.legal_entity)
    order by x.${ctx.col("values", "definition")}, x.${FIELD_VALUE_ENTITY_COLUMN} nulls last)`
    : values;

  const entityChecked = entityCheck(ctx, "save_field_definition.entity");
  const entityGuard = entityChecked === "" ? "" : `${entityChecked}\n  `;

  const visible = inline
    ? "true"
    : `not coalesce(d.${ctx.col("definitions", "sensitive")}, false)
        or ${ctx.scope.can(`v.${ctx.col("values", "tenant")}`, `coalesce(d.${ctx.col("definitions", "permission")}, ${sensitive})`)}`;

  return `${schemaPreamble(ctx)}
${inline ? "" : `${formatValidatorSql(ctx.schemaName, CUSTOM_FIELD_VALIDATORS)}\n`}-- A sensitive value is returned only when the caller holds the field's
-- permission, or custom_fields.sensitive.read when the field names none.
${tables}
create or replace function ${ctx.fn("save_field_definition")}(tenant ${ctx.idType}, entity text, key text, label text, type text, sensitive boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_inserted boolean;
  v_last text;
  v_rank text;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("save_field_definition.tenant", manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to manage custom fields")}
  end if;
  ${
    inline
      ? fail("FIELD_INLINE", "inline fields have no definition row", "0A000")
      : `${entityGuard}${
          ranked
            ? `select max(d.${rank} collate "C") into v_last from ${definitions} d
    where d.${ctx.col("definitions", "tenant")} = save_field_definition.tenant and d.${ctx.col("definitions", "entity")} = save_field_definition.entity;
  v_rank := ${rankAfter("v_last")};
  `
            : ""
        }insert into ${definitions} (${ctx.col("definitions", "tenant")}, ${ctx.col("definitions", "entity")}, ${ctx.col("definitions", "key")}, ${ctx.col("definitions", "label")}, ${ctx.col("definitions", "type")}, ${ctx.col("definitions", "sensitive")}${ranked ? `, ${rank}` : ""})
  values (save_field_definition.tenant, save_field_definition.entity, save_field_definition.key, save_field_definition.label, save_field_definition.type, coalesce(save_field_definition.sensitive, false)${ranked ? ", v_rank" : ""})
  on conflict (${ctx.col("definitions", "tenant")}, ${ctx.col("definitions", "entity")}, ${ctx.col("definitions", "key")})
  do update set ${ctx.col("definitions", "label")} = excluded.${ctx.col("definitions", "label")}, ${ctx.col("definitions", "sensitive")} = excluded.${ctx.col("definitions", "sensitive")}
  returning ${ctx.col("definitions", "id")}, xmax = 0 into v_id, v_inserted;`
  }
  ${createdOrUpdated("v_inserted", (verb) =>
    ctx.record({
      type: `field_definition.${verb}`,
      payload: `jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity)`,
      subject: `'custom-fields/' || coalesce(v_id::text, save_field_definition.key)`,
      tenant: "save_field_definition.tenant",
      audit: false,
    }),
  )}
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${ctx.fn("save_field_definition")}(${ctx.idType}, text, text, text, text, boolean)`)}

${perEntity ? `drop function if exists ${ctx.fn("read_field_values")}(${ctx.idType}, text, text);\n` : ""}create or replace function ${ctx.fn("read_field_values")}(tenant ${ctx.idType}, subject_type text, subject_id text${perEntity ? ", legal_entity uuid default null" : ""})
returns jsonb
language plpgsql
${audited ? "volatile" : ctx.readVolatility()}
security definer
set search_path = ''
as $$
declare
  v_values jsonb;${encrypted === "" ? "" : `\n  v_key text;`}${audited ? `\n  v_read jsonb;` : ""}
begin${encrypted === "" ? "" : `\n  v_key := ${encryption?.fn("field_key")}('tenant:' || read_field_values.tenant::text, false);`}
  select coalesce(jsonb_agg(jsonb_build_object('id', v.${ctx.col("values", "id")}, 'text', ${encrypted === "" ? `v.${ctx.col("values", "valueText")}` : `case when ${encrypted} then ${encryption?.fn("field_open")}(v_key, v.${ctx.col("values", "valueText")}) else v.${ctx.col("values", "valueText")} end`})), '[]'::jsonb)${
    audited
      ? `,
    jsonb_agg(v.${ctx.col("values", "id")}) filter (where ${inline ? "true" : [encrypted, `coalesce(d.${ctx.col("definitions", "sensitive")}, false)`].filter((part) => part !== "").join(" or ")})`
      : ""
  }
  into v_values${audited ? ", v_read" : ""}
  from ${readableValues} v
  ${inline ? "" : `left join ${definitions} d on d.${ctx.col("definitions", "id")} = v.${ctx.col("values", "definition")}`}
  where v.${ctx.col("values", "tenant")} = read_field_values.tenant
    and v.${ctx.col("values", "subjectType")} = read_field_values.subject_type
    and v.${ctx.col("values", "subjectId")} = read_field_values.subject_id
    and (auth.role() = 'service_role' or ${fieldReadGate(
      "read_field_values.subject_type",
      recordSubjects,
      readAccess === "record" && recordSubjects.length === subjects.length,
      {
        record: subjectReadable(ctx, recordSubjects, {
          type: "read_field_values.subject_type",
          id: "read_field_values.subject_id",
          tenant: "read_field_values.tenant",
        }),
        tenant: ctx.scope.can("read_field_values.tenant", read),
      },
    )})
    and (${visible});${
      audited
        ? `
  if v_read is not null then
    ${ctx.audit({
      type: "field_value.viewed",
      payload: `jsonb_build_object('organizationId', read_field_values.tenant, 'subjectType', read_field_values.subject_type, 'subjectId', read_field_values.subject_id, 'ids', v_read)`,
      subject: `'field-values/' || read_field_values.subject_id`,
      tenant: "read_field_values.tenant",
      audit: {
        category: "read",
        targetType: "field_value",
        recordId: "read_field_values.subject_id",
        summary: `'Read ' || jsonb_array_length(v_read)::text || ' protected field value(s) of ' || read_field_values.subject_type`,
      },
    })}
  end if;`
        : ""
    }${
      logRead === ""
        ? ""
        : `
  if jsonb_array_length(v_values) > 0 then
    ${logRead}
  end if;`
    }
  return v_values;
end;
$$;
${userGrant(`${ctx.fn("read_field_values")}(${ctx.idType}, text, text${perEntity ? ", uuid" : ""})`)}

${perEntity ? `drop function if exists ${ctx.fn("set_field_value")}(${ctx.idType}, text, text, uuid, text);\n` : ""}create or replace function ${ctx.fn("set_field_value")}(tenant ${ctx.idType}, subject_type text, subject_id text, definition uuid, value text${perEntity ? ", legal_entity uuid default null" : ""})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("set_field_value.tenant", manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to set custom fields")}
  end if;${
    subjectWrite === undefined
      ? ""
      : `
  if not ${subjectWrite} then
    ${fail("FIELD_SUBJECT_FORBIDDEN", "not allowed to set fields on this record")}
  end if;`
  }${
    inline
      ? ""
      : `
  if exists (select 1 from ${definitions} d where d.${ctx.col("definitions", "id")} = set_field_value.definition and not (${customFieldValueCheck(`d.${ctx.col("definitions", "type")}`, "set_field_value.value", ctx.schemaName)})) then
    ${fail("FIELD_VALUE_INVALID", "the value doesn't match the field's format", "22023")}
  end if;`
  }
  insert into ${values} (${ctx.col("values", "tenant")}, ${ctx.has("values", "definition") && !inline ? `${ctx.col("values", "definition")}, ` : ""}${ctx.col("values", "subjectType")}, ${ctx.col("values", "subjectId")}, ${ctx.col("values", "valueText")}${perEntity ? `, ${FIELD_VALUE_ENTITY_COLUMN}` : ""})
  values (set_field_value.tenant, ${ctx.has("values", "definition") && !inline ? "set_field_value.definition, " : ""}set_field_value.subject_type, set_field_value.subject_id, ${
    encrypted === ""
      ? "set_field_value.value"
      : `case when exists (select 1 from ${definitions} d where d.${ctx.col("definitions", "id")} = set_field_value.definition and d.${ctx.col("definitions", "encrypted")}) then ${encryption?.fn("field_encrypt")}('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end`
  }${perEntity ? ", set_field_value.legal_entity" : ""})
  returning ${ctx.col("values", "id")} into v_id;
  ${ctx.record({
    type: "field_value.set",
    payload: `jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id)`,
    subject: `'field-values/' || v_id::text`,
    tenant: "set_field_value.tenant",
    audit: false,
  })}
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${ctx.fn("set_field_value")}(${ctx.idType}, text, text, uuid, text${perEntity ? ", uuid" : ""})`)}

create or replace function ${ctx.fn("delete_field_definition")}(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  ${
    inline
      ? fail("FIELD_INLINE", "inline fields have no definition row", "0A000")
      : `select ${ctx.col("definitions", "tenant")} into v_tenant from ${definitions} where ${ctx.col("definitions", "id")} = delete_field_definition.definition;
  if not found then
    ${fail("FIELD_NOT_FOUND", "field not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to manage custom fields")}
  end if;
  delete from ${definitions} where ${ctx.col("definitions", "id")} = delete_field_definition.definition;`
  }
  ${ctx.record({
    type: "field_definition.deleted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', delete_field_definition.definition)`,
    subject: `'custom-fields/' || delete_field_definition.definition::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${ctx.fn("delete_field_definition")}(uuid)`)}
${inline ? "" : listDefinitions(ctx, definitions, rank, read)}${ranked ? rankDefinition(ctx, definitions, rank, manage) : ""}${encrypted === "" ? "" : encryptDefinition(ctx, definitions, values, manage)}${packsOn(ctx) ? installFieldPack(ctx, manage) : ""}${
    importsOn(ctx)
      ? importFieldValue(ctx, {
          seal: (value) =>
            encrypted === ""
              ? value
              : `case when exists (select 1 from ${definitions} d where d.${ctx.col("definitions", "id")} = v_definition and d.${ctx.col("definitions", "encrypted")}) then ${encryption?.fn("field_encrypt")}('tenant:' || v_tenant::text, ${value}) else ${value} end`,
          record: ctx.record({
            type: "field_value.set",
            payload: `jsonb_build_object('organizationId', v_tenant, 'id', v_row, 'subjectType', v_type, 'subjectId', v_subject)`,
            subject: `'field-values/' || v_row::text`,
            tenant: "v_tenant",
            audit: false,
          }),
        })
      : ""
  }`;
}

/** `options.entityMap`: stored entity to the registered subject type. */
function entityMapOf(ctx: BlockSqlContext): Readonly<Record<string, string>> {
  const raw = ctx.option("entityMap");

  if (raw === undefined) {
    return {};
  }

  if (
    typeof raw !== "object" ||
    raw === null ||
    Array.isArray(raw) ||
    !Object.values(raw).every((to) => typeof to === "string")
  ) {
    throw new Error(
      "custom-fields: options.entityMap maps stored entity names to subject types, such as { invoice: 'sales_invoice' }.",
    );
  }

  return Object.fromEntries(Object.entries(raw));
}

/**
 * The pack columns of a definitions table the module doesn't create, added when
 * the table has them mapped.
 */
function packColumns(ctx: BlockSqlContext, definitions: string): string {
  return packsOn(ctx)
    ? `alter table ${definitions} add column if not exists ${ctx.col("definitions", "pack")} text;
alter table ${definitions} add column if not exists ${ctx.col("definitions", "packVersion")} integer;
`
    : "";
}

/**
 * Whether definitions can be encrypted: a definition table with the column, and
 * the field-encryption block.
 */
function encrypts(ctx: BlockSqlContext): boolean {
  return (
    ctx.text("layout", "normalized") !== "inline" &&
    ctx.has("definitions", "encrypted") &&
    ctx.installed("field-encryption")
  );
}

/**
 * `encrypt_field_definition(definition)`: turns encryption on for a text field
 * and encrypts the values it already has with the tenant's data key. There is
 * no way back: a field that holds ciphertext stays encrypted.
 */
function encryptDefinition(
  ctx: BlockSqlContext,
  definitions: string,
  values: string,
  manage: string,
): string {
  const encryption = ctx.of("field-encryption");
  const id = ctx.col("definitions", "id");
  const encrypted = ctx.col("definitions", "encrypted");
  const valueText = ctx.col("values", "valueText");

  return `
-- Encrypts a text field and the values it already has. It can't be undone.
create or replace function ${ctx.fn("encrypt_field_definition")}(definition uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_type text;
  v_key text;
begin
  select ${ctx.col("definitions", "tenant")}, ${ctx.col("definitions", "type")} into v_tenant, v_type from ${definitions} where ${id} = encrypt_field_definition.definition;
  if not found then
    ${fail("FIELD_NOT_FOUND", "field not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to manage custom fields")}
  end if;
  if v_type not in (${ENCRYPTABLE_TYPES.map((type) => sqlString(type)).join(", ")}) then
    ${fail("FIELD_NOT_ENCRYPTABLE", "only text fields can be encrypted", "22023")}
  end if;
  v_key := ${encryption.fn("field_key")}('tenant:' || v_tenant::text, true);
  update ${definitions} set ${encrypted} = true where ${id} = encrypt_field_definition.definition;
  update ${values} set ${valueText} = ${encryption.fn("field_seal")}(v_key, ${valueText})
  where ${ctx.col("values", "definition")} = encrypt_field_definition.definition
    and ${valueText} is not null
    and left(${valueText}, ${String(FIELD_CIPHER_PREFIX.length)}) <> ${sqlString(FIELD_CIPHER_PREFIX)};
  return true;
end;
$$;
${userGrant(`${ctx.fn("encrypt_field_definition")}(uuid)`)}
`;
}

/**
 * The type check, named so a later release can widen it: dropping the inline
 * check an older install created, then adding the named one.
 */
function typeCheck(ctx: BlockSqlContext, definitions: string): string {
  const column = ctx.colName("definitions", "type");
  const legacy = `${ctx.tableName("definitions").name}_${column}_check`;

  return `alter table ${definitions} drop constraint if exists ${sqlIdent(legacy)};
${ensureCheck(definitions, ctx.naming.rename("bsb_field_definitions_type"), `${sqlIdent(column)} in (${CUSTOM_FIELD_TYPES.map(sqlString).join(", ")})`)}`;
}

function listDefinitions(
  ctx: BlockSqlContext,
  definitions: string,
  rank: string,
  read: string,
): string {
  const order =
    rank === ""
      ? `d.${ctx.col("definitions", "key")}`
      : `d.${rank} collate "C", d.${ctx.col("definitions", "key")}`;

  return `
-- The definitions of one entity in display order.
create or replace function ${ctx.fn("list_field_definitions")}(tenant ${ctx.idType}, entity text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.${ctx.col("definitions", "id")},
    'entity', d.${ctx.col("definitions", "entity")},
    'key', d.${ctx.col("definitions", "key")},
    'label', d.${ctx.col("definitions", "label")},
    'type', d.${ctx.col("definitions", "type")},
    'required', d.${ctx.col("definitions", "required")},
    'sensitive', d.${ctx.col("definitions", "sensitive")},${
      ctx.has("definitions", "encrypted")
        ? `
    'encrypted', d.${ctx.col("definitions", "encrypted")},`
        : ""
    }
    ${
      packsOn(ctx)
        ? `'pack', d.${ctx.col("definitions", "pack")},
    'packVersion', d.${ctx.col("definitions", "packVersion")},
    `
        : ""
    }'rank', ${rank === "" ? "null" : `d.${rank}`}
  ) order by ${order}), '[]'::jsonb)
  from ${definitions} d
  where d.${ctx.col("definitions", "tenant")} = list_field_definitions.tenant
    and d.${ctx.col("definitions", "entity")} = list_field_definitions.entity
    and (auth.role() = 'service_role' or ${ctx.scope.can("list_field_definitions.tenant", read)})
$$;
${userGrant(`${ctx.fn("list_field_definitions")}(${ctx.idType}, text)`)}
`;
}

function rankDefinition(
  ctx: BlockSqlContext,
  definitions: string,
  rank: string,
  manage: string,
): string {
  return `
-- Sets a field's rank key, from rankBetween over its neighbours' keys.
create or replace function ${ctx.fn("rank_field_definition")}(definition uuid, rank text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  if rank_field_definition.rank is null or rank_field_definition.rank !~ ${RANK_KEY_PATTERN} then
    ${fail("FIELD_RANK_INVALID", "not a rank key", "22023")}
  end if;
  select ${ctx.col("definitions", "tenant")} into v_tenant from ${definitions} where ${ctx.col("definitions", "id")} = rank_field_definition.definition;
  if not found then
    ${fail("FIELD_NOT_FOUND", "field not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to manage custom fields")}
  end if;
  update ${definitions} set ${rank} = rank_field_definition.rank where ${ctx.col("definitions", "id")} = rank_field_definition.definition;
  return true;
end;
$$;
${userGrant(`${ctx.fn("rank_field_definition")}(uuid, text)`)}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  if (ctx.text("layout", "normalized") === "keyed") {
    return keyedContract();
  }

  return [
    {
      name: "save_field_definition",
      args: ["{id}", "text", "text", "text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "read_field_values",
      args: [
        "{id}",
        "text",
        "text",
        ...(perEntityValues(ctx) ? (["uuid"] as const) : []),
      ],
      returns: "jsonb",
    },
    {
      name: "set_field_value",
      args: [
        "{id}",
        "text",
        "text",
        "uuid",
        "text",
        ...(perEntityValues(ctx) ? (["uuid"] as const) : []),
      ],
      returns: "jsonb",
    },
    { name: "delete_field_definition", args: ["uuid"], returns: "boolean" },
    ...(ctx.text("layout", "normalized") === "inline"
      ? []
      : [
          {
            name: "list_field_definitions",
            args: ["{id}", "text"],
            returns: "jsonb",
          },
        ]),
    ...(encrypts(ctx)
      ? [
          {
            name: "encrypt_field_definition",
            args: ["uuid"],
            returns: "boolean",
          },
        ]
      : []),
    ...(packsOn(ctx)
      ? [
          {
            name: "install_field_pack",
            args: ["{id}", "jsonb"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(ctx.text("layout", "normalized") !== "inline" &&
    ctx.has("definitions", "rank")
      ? [
          {
            name: "rank_field_definition",
            args: ["uuid", "text"],
            returns: "boolean",
          },
        ]
      : []),
  ];
}

export const CUSTOM_FIELDS: BlockSqlDefinition = {
  name: "custom-fields",
  scopes: ["tenant"],
  title: "Custom fields",
  description:
    "Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.",
  requires: ["memberships", "permissions"],
  integrates: [
    "outbox",
    "field-encryption",
    "audit",
    "subjects",
    "legal-entities",
    "imports",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  version: 4,
  contributes: { imports: fieldValueImportTargets },
  upgrades: [
    {
      from: 1,
      description:
        "Field definitions order by a fractional rank key instead of an integer position; rank_field_definition sets it.",
      sql: (ctx) => {
        if (
          !ctx.owns("definitions") ||
          ctx.text("layout", "normalized") === "inline"
        ) {
          return "";
        }

        const definitions = ctx.table("definitions");
        const rank = ctx.col("definitions", "rank");

        return `alter table ${definitions} add column if not exists ${rank} text collate "C";
${rankBackfill({
  table: definitions,
  id: ctx.col("definitions", "id"),
  rank,
  partition: [
    ctx.col("definitions", "tenant"),
    ctx.col("definitions", "entity"),
  ],
  orderBy: `position, ${ctx.col("definitions", "key")}, ${ctx.col("definitions", "id")}`,
})}
alter table ${definitions} alter column ${rank} set default 'V', alter column ${rank} set not null;
alter table ${definitions} drop column if exists position;`;
      },
    },
    {
      from: 2,
      description:
        "Field definitions gain an encrypted flag; encrypt_field_definition encrypts a text field's values with the tenant's data key.",
      sql: (ctx) =>
        !ctx.owns("definitions") ||
        ctx.text("layout", "normalized") === "inline" ||
        !ctx.has("definitions", "encrypted")
          ? ""
          : `alter table ${ctx.table("definitions")} add column if not exists ${ctx.col("definitions", "encrypted")} boolean not null default false;`,
    },
    {
      from: 3,
      description:
        "Field definitions name a registered subject type (FIELD_ENTITY_UNKNOWN), carry the field pack they came from, and install_field_pack installs a pack idempotently; blocks.custom-fields.options.entityMap renames stored entities, and with the legal-entities block field_values gain a nullable legal_entity_id.",
      sql: (ctx) => {
        if (
          !ctx.owns("definitions") ||
          ctx.text("layout", "normalized") === "inline"
        ) {
          return "";
        }

        const definitions = ctx.table("definitions");
        const entity = ctx.col("definitions", "entity");
        const key = ctx.col("definitions", "key");
        const tenant = ctx.col("definitions", "tenant");
        const values = ctx.table("values");

        const renames = Object.entries(entityMapOf(ctx)).map(
          ([
            from,
            to,
          ]) => `update ${definitions} d set ${entity} = ${sqlString(to)}
where d.${entity} = ${sqlString(from)}
  and not exists (select 1 from ${definitions} e where e.${tenant} = d.${tenant} and e.${entity} = ${sqlString(to)} and e.${key} = d.${key});
update ${values} set ${ctx.col("values", "subjectType")} = ${sqlString(to)} where ${ctx.col("values", "subjectType")} = ${sqlString(from)};`,
        );

        return `${packColumns(ctx, definitions)}${renames.join("\n")}`;
      },
    },
  ],
  names: NAMES,
  contract,
  build,
  unusedPermissions: (ctx) => {
    if (ctx.text("layout", "normalized") !== "keyed") {
      return [];
    }

    const { readAccess } = keyedOptions(ctx);
    const subjects = fieldSubjects(ctx);

    return [
      "sensitive",
      ...(readAccess === "record" &&
      recordReadSubjects(subjects, readAccess).length === subjects.length
        ? ["read"]
        : []),
    ];
  },
};
