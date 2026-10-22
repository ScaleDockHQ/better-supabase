import type { CustomFieldsEvents } from "../../blocks/custom-fields/events.ts";
import type { CustomFieldType } from "../../core/contracts/field-formats.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { CUSTOM_FIELD_TYPES } from "../../core/contracts/field-formats.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { RANK_KEY_PATTERN, rankAfter, rankBackfill } from "../rank-sql.ts";
import {
  ensureCheck,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";
import { FIELD_CIPHER_PREFIX } from "./field-encryption.ts";

/** The custom field types whose values `encrypt_field_definition` encrypts. */
const ENCRYPTABLE_TYPES: readonly CustomFieldType[] = ["text", "email", "url"];

const EVENTS: ModuleEvents<CustomFieldsEvents> = {
  "custom_field.saved": {
    subject: "custom-fields",
    payload: ["organizationId", "id", "entity"],
  },
  "custom_field.deleted": {
    subject: "custom-fields",
    payload: ["organizationId", "id"],
  },
  "field_value.set": {
    subject: "field-values",
    payload: ["organizationId", "id", "subjectType", "subjectId"],
  },
  "field_value.viewed": {
    subject: "field-values",
    payload: ["organizationId", "subjectType", "subjectId", "ids"],
  },
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: ["layout", "auditReads"],
  tables: {
    definitions: {
      name: "field_definitions",
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
      },
      optional: ["rank", "encrypted"],
    },
    options: {
      name: "field_options",
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
      },
      optional: ["definition", "valueJson"],
    },
  },
};

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const inline = ctx.text("layout", "normalized") === "inline";

  if (
    ctx.text("layout", "normalized") !== "inline" &&
    ctx.text("layout", "normalized") !== "normalized"
  ) {
    throw new TypeError(
      'blocks.custom-fields.options.layout must be "normalized" or "inline"',
    );
  }

  const definitions = ctx.table("definitions");
  const ranked = !inline && ctx.has("definitions", "rank");
  const rank = ranked ? ctx.col("definitions", "rank") : "";
  const values = ctx.table("values");
  const manage = ctx.permission("manage", OPERATIONS["custom-fields.manage"]);
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
${ctx.has("definitions", "encrypted") ? `  ${ctx.col("definitions", "encrypted")} boolean not null default false,\n` : ""}${ranked ? `  ${rank} text collate "C" not null default 'V',\n` : ""}  unique (${ctx.col("definitions", "tenant")}, ${ctx.col("definitions", "entity")}, ${ctx.col("definitions", "key")})
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
  ${inline || !ctx.has("values", "definition") ? "" : `, unique (${ctx.col("values", "tenant")}, ${ctx.col("values", "subjectType")}, ${ctx.col("values", "subjectId")}, ${ctx.col("values", "definition")})`}
);
${lockTable(values, { read: true })}
${inline || !ctx.has("values", "definition") ? "" : `create index if not exists field_values_definition_idx on ${values} (${ctx.col("values", "definition")});`}
`
    : "";

  const visible = inline
    ? "true"
    : `not coalesce(d.${ctx.col("definitions", "sensitive")}, false)
        or ${ctx.scope.can(`v.${ctx.col("values", "tenant")}`, `coalesce(d.${ctx.col("definitions", "permission")}, ${sensitive})`)}`;

  return `${schemaPreamble(ctx)}
-- A sensitive value is returned only when the caller holds the field's
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
  v_last text;
  v_rank text;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("save_field_definition.tenant", manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to manage custom fields")}
  end if;
  ${
    inline
      ? fail("FIELD_INLINE", "inline fields have no definition row", "0A000")
      : `${
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
  returning ${ctx.col("definitions", "id")} into v_id;`
  }
  ${ctx.record({
    type: "custom_field.saved",
    payload: `jsonb_build_object('organizationId', save_field_definition.tenant, 'id', v_id, 'entity', save_field_definition.entity)`,
    subject: `'custom-fields/' || coalesce(v_id::text, save_field_definition.key)`,
    tenant: "save_field_definition.tenant",
    audit: false,
  })}
  return jsonb_build_object('id', v_id);
end;
$$;
${userGrant(`${ctx.fn("save_field_definition")}(${ctx.idType}, text, text, text, text, boolean)`)}

create or replace function ${ctx.fn("read_field_values")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language plpgsql
${audited ? "volatile" : "stable"}
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
  from ${values} v
  ${inline ? "" : `left join ${definitions} d on d.${ctx.col("definitions", "id")} = v.${ctx.col("values", "definition")}`}
  where v.${ctx.col("values", "tenant")} = read_field_values.tenant
    and v.${ctx.col("values", "subjectType")} = read_field_values.subject_type
    and v.${ctx.col("values", "subjectId")} = read_field_values.subject_id
    and (auth.role() = 'service_role' or ${ctx.scope.can("read_field_values.tenant", read)})
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
    }
  return v_values;
end;
$$;
${userGrant(`${ctx.fn("read_field_values")}(${ctx.idType}, text, text)`)}

create or replace function ${ctx.fn("set_field_value")}(tenant ${ctx.idType}, subject_type text, subject_id text, definition uuid, value text)
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
  end if;
  insert into ${values} (${ctx.col("values", "tenant")}, ${ctx.has("values", "definition") && !inline ? `${ctx.col("values", "definition")}, ` : ""}${ctx.col("values", "subjectType")}, ${ctx.col("values", "subjectId")}, ${ctx.col("values", "valueText")})
  values (set_field_value.tenant, ${ctx.has("values", "definition") && !inline ? "set_field_value.definition, " : ""}set_field_value.subject_type, set_field_value.subject_id, ${
    encrypted === ""
      ? "set_field_value.value"
      : `case when exists (select 1 from ${definitions} d where d.${ctx.col("definitions", "id")} = set_field_value.definition and d.${ctx.col("definitions", "encrypted")}) then ${encryption?.fn("field_encrypt")}('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end`
  })
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
${userGrant(`${ctx.fn("set_field_value")}(${ctx.idType}, text, text, uuid, text)`)}

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
    type: "custom_field.deleted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', delete_field_definition.definition)`,
    subject: `'custom-fields/' || delete_field_definition.definition::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${ctx.fn("delete_field_definition")}(uuid)`)}
${inline ? "" : listDefinitions(ctx, definitions, rank, read)}${ranked ? rankDefinition(ctx, definitions, rank, manage) : ""}${encrypted === "" ? "" : encryptDefinition(ctx, definitions, values, manage)}`;
}

/**
 * Whether definitions can be encrypted: a definition table with the column, and
 * the field-encryption block.
 */
function encrypts(ctx: ModuleContext): boolean {
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
  ctx: ModuleContext,
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
function typeCheck(ctx: ModuleContext, definitions: string): string {
  const column = ctx.colName("definitions", "type");
  const legacy = `${ctx.tableName("definitions").name}_${column}_check`;

  return `alter table ${definitions} drop constraint if exists ${sqlIdent(legacy)};
${ensureCheck(definitions, "bs_field_definitions_type", `${sqlIdent(column)} in (${CUSTOM_FIELD_TYPES.map(sqlString).join(", ")})`)}`;
}

function listDefinitions(
  ctx: ModuleContext,
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
    'sensitive', d.${ctx.col("definitions", "sensitive")},
    'rank', ${rank === "" ? "null" : `d.${rank}`}
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
  ctx: ModuleContext,
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

function contract(ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "save_field_definition",
      args: ["{id}", "text", "text", "text", "text", "boolean"],
      returns: "jsonb",
    },
    {
      name: "read_field_values",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "set_field_value",
      args: ["{id}", "text", "text", "uuid", "text"],
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

export const CUSTOM_FIELDS: ModuleDefinition = {
  name: "custom-fields",
  scopes: ["tenant"],
  title: "Custom fields",
  description:
    "Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.",
  requires: ["tenant", "access"],
  integrates: ["outbox", "field-encryption", "audit"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "Field definitions order by a fractional rank key instead of an integer position; rank_field_definition sets it.",
      sql: (ctx) => {
        if (!ctx.manages || ctx.text("layout", "normalized") === "inline") {
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
        !ctx.manages ||
        ctx.text("layout", "normalized") === "inline" ||
        !ctx.has("definitions", "encrypted")
          ? ""
          : `alter table ${ctx.table("definitions")} add column if not exists ${ctx.col("definitions", "encrypted")} boolean not null default false;`,
    },
  ],
  names: NAMES,
  contract,
  build,
};
