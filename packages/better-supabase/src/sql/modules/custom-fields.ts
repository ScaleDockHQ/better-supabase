import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { RANK_KEY_PATTERN, rankAfter, rankBackfill } from "../rank-sql.ts";
import { fail, lockTable, schemaPreamble, userGrant } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

const EVENTS: ModuleEvents = {
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
};

const NAMES: ModuleNames = {
  events: EVENTS,
  options: ["layout"],
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
      },
      optional: ["rank"],
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
  if (ctx.mode === "custom") return "";
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
  ${ctx.col("definitions", "type")} text not null check (${ctx.col("definitions", "type")} in ('text', 'number', 'date', 'bool', 'option', 'json')),
  ${ctx.col("definitions", "required")} boolean not null default false,
  ${ctx.col("definitions", "sensitive")} boolean not null default false,
  ${ctx.col("definitions", "permission")} text,
${ranked ? `  ${rank} text collate "C" not null default 'V',\n` : ""}  unique (${ctx.col("definitions", "tenant")}, ${ctx.col("definitions", "entity")}, ${ctx.col("definitions", "key")})
);
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
        or coalesce(better_supabase.can('tenant', v.${ctx.col("values", "tenant")}, coalesce(d.${ctx.col("definitions", "permission")}, ${sensitive})), false)`;
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_field_definition.tenant, ${manage}), false)) then
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
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', v.${ctx.col("values", "id")}, 'text', v.${ctx.col("values", "valueText")})), '[]'::jsonb)
  from ${values} v
  ${inline ? "" : `left join ${definitions} d on d.${ctx.col("definitions", "id")} = v.${ctx.col("values", "definition")}`}
  where v.${ctx.col("values", "tenant")} = read_field_values.tenant
    and v.${ctx.col("values", "subjectType")} = read_field_values.subject_type
    and v.${ctx.col("values", "subjectId")} = read_field_values.subject_id
    and (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', read_field_values.tenant, ${read}), false))
    and (${visible})
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, ${manage}), false)) then
    ${fail("FIELD_FORBIDDEN", "not allowed to set custom fields")}
  end if;
  insert into ${values} (${ctx.col("values", "tenant")}, ${ctx.has("values", "definition") && !inline ? `${ctx.col("values", "definition")}, ` : ""}${ctx.col("values", "subjectType")}, ${ctx.col("values", "subjectId")}, ${ctx.col("values", "valueText")})
  values (set_field_value.tenant, ${ctx.has("values", "definition") && !inline ? "set_field_value.definition, " : ""}set_field_value.subject_type, set_field_value.subject_id, set_field_value.value)
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, ${manage}), false)) then
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
${ranked ? rankDefinition(ctx, definitions, rank, manage) : ""}`;
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, ${manage}), false)) then
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
  title: "Custom fields",
  description:
    "Field definitions, options and typed values. A sensitive value is readable only with the field's permission. Inline layout stores the definition on the value row.",
  requires: ["tenant", "access"],
  integrates: ["outbox"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
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
  ],
  names: NAMES,
  contract,
  build,
};
