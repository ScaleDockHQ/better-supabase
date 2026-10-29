import type { CustomFieldType } from "../../core/contracts/field-formats.ts";
import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BoundSubject, PolymorphicColumns } from "../subject-columns.ts";
import type { Subject } from "../subjects.ts";

import { CUSTOM_FIELD_TYPES } from "../../core/contracts/field-formats.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { asColumnType } from "../column-type.ts";
import { customFieldValueCheck } from "../format-checks.ts";
import { fail, lockTable, userGrant } from "../shared.ts";
import {
  boundRowSubject,
  boundSubjectMatch,
  boundSubjects as boundOf,
} from "../subject-columns.ts";
import {
  andSubjectAction,
  subjectActionCheck,
  subjectReadable,
  subjectsOption,
} from "../subjects.ts";

/** The value column each field type is stored in, when the table maps it. */
const VALUE_COLUMNS: Readonly<Record<string, readonly CustomFieldType[]>> = {
  valueNumber: ["number", "rating", "currency"],
  valueDate: ["date"],
  valueBool: ["bool"],
  valueJson: ["json", "multi_option"],
  valueUrl: ["url"],
  valueEmail: ["email"],
};

/** `blocks.custom-fields.options.rankType` and `readAccess`. */
export interface KeyedOptions {
  readonly rankType: "text" | "integer";
  readonly readAccess: "tenant" | "record";
}

export function keyedOptions(ctx: BlockSqlContext): KeyedOptions {
  const rankType = ctx.text("rankType", "text");
  const readAccess = ctx.text("readAccess", "tenant");

  if (rankType !== "text" && rankType !== "integer") {
    throw new TypeError(
      'blocks.custom-fields.options.rankType must be "text" or "integer"',
    );
  }

  if (readAccess !== "tenant" && readAccess !== "record") {
    throw new TypeError(
      'blocks.custom-fields.options.readAccess must be "tenant" or "record"',
    );
  }

  return { rankType, readAccess };
}

/** `blocks.custom-fields.on`, with `column` read per subject. */
export function fieldSubjects(
  ctx: BlockSqlContext,
): readonly (readonly [string, Subject])[] {
  return subjectsOption(ctx, ["column"]);
}

const boundSubjects = (ctx: BlockSqlContext): readonly BoundSubject[] =>
  boundOf(fieldSubjects(ctx), "blocks.custom-fields.on");

/** Whether the values table keeps `subject_type` and `subject_id`. */
const polymorphic = (ctx: BlockSqlContext): boolean =>
  ctx.has("values", "subjectType") && ctx.has("values", "subjectId");

const polyColumns = (ctx: BlockSqlContext): PolymorphicColumns | undefined =>
  polymorphic(ctx)
    ? {
        type: ctx.col("values", "subjectType"),
        id: ctx.col("values", "subjectId"),
      }
    : undefined;

/**
 * Throws unless the subject columns are present, or every subject names its own
 * column in keyed layout.
 */
export function checkSubjectColumns(
  ctx: BlockSqlContext,
  keyed: boolean,
): void {
  if (polymorphic(ctx)) {
    return;
  }

  const bound = boundSubjects(ctx);
  const subjects = fieldSubjects(ctx);

  if (!keyed || subjects.length === 0 || bound.length !== subjects.length) {
    throw new TypeError(
      'blocks.custom-fields.columns.values.subjectType and subjectId can be null only with layout "keyed" and a column in every blocks.custom-fields.on.<type>',
    );
  }
}

/** Whether row `alias` belongs to the subject `type`/`id` (text expressions). */
const subjectMatch = (
  ctx: BlockSqlContext,
  alias: string,
  type: string,
  id: string,
): string =>
  boundSubjectMatch(boundSubjects(ctx), polyColumns(ctx), alias, type, id);

/** The subject type and id (text) of row `alias`. */
function rowSubject(
  ctx: BlockSqlContext,
  alias: string,
): { readonly type: string; readonly id: string } {
  const bound = boundSubjects(ctx);

  return bound.length === 0
    ? {
        type: `${alias}.${ctx.col("values", "subjectType")}::text`,
        id: `${alias}.${ctx.col("values", "subjectId")}`,
      }
    : boundRowSubject(bound, polyColumns(ctx), alias);
}

/** The block's field type of row `alias`, through `values.values.type`. */
const typeOf = (ctx: BlockSqlContext, alias: string): string =>
  ctx.label("values", "type", `${alias}.${ctx.col("values", "type")}`);

/** The value of row `alias` as `jsonb`, from the column its type uses. */
function valueJson(ctx: BlockSqlContext, alias: string): string {
  const v = (logical: string): string =>
    `${alias}.${ctx.col("values", logical)}`;

  const type = typeOf(ctx, alias);

  const whens = Object.entries(VALUE_COLUMNS).flatMap(([logical, types]) =>
    ctx.has("values", logical)
      ? [
          `when ${type} in (${types.map((item) => sqlString(item)).join(", ")}) then ${logical === "valueJson" ? v(logical) : `to_jsonb(${v(logical)})`}`,
        ]
      : [],
  );

  return whens.length === 0
    ? `to_jsonb(${v("valueText")})`
    : `case ${whens.join(" ")} else to_jsonb(${v("valueText")}) end`;
}

/** One value row `alias` as the JSON the keyed functions return. */
function rowJson(
  ctx: BlockSqlContext,
  alias: string,
  integerRank = false,
): string {
  const v = (logical: string): string =>
    `${alias}.${ctx.col("values", logical)}`;

  const or = (logical: string): string =>
    ctx.has("values", logical) ? v(logical) : "null";

  const subject = rowSubject(ctx, alias);

  return `jsonb_build_object('id', ${v("id")}, 'subjectType', ${subject.type}, 'subjectId', ${subject.id}, 'key', ${v("key")}, 'label', ${v("label")}, 'type', ${typeOf(ctx, alias)}, 'rank', ${integerRank && ctx.has("values", "rank") ? `${v("rank")}::text` : or("rank")}, 'value', ${valueJson(ctx, alias)}, 'createdAt', ${or("createdAt")}, 'updatedAt', ${or("updatedAt")})`;
}

/**
 * Each value column with the expression it gets for `type` (a block label) and
 * `value` (`jsonb`): the column of the type gets the value, every other value
 * column null.
 */
function valueAssignments(
  ctx: BlockSqlContext,
  type: string,
  value: string,
): readonly (readonly [string, string])[] {
  const casts: Readonly<Record<string, string>> = {
    valueNumber: "numeric",
    valueDate: "date",
    valueBool: "boolean",
  };

  const used = Object.entries(VALUE_COLUMNS).filter(([logical]) =>
    ctx.has("values", logical),
  );

  const own = used.map(([logical, types]): readonly [string, string] => {
    const cast = casts[logical];

    const expression =
      logical === "valueJson"
        ? value
        : cast === undefined
          ? `${value} #>> '{}'`
          : `(${value} #>> '{}')::${cast}`;

    return [
      ctx.col("values", logical),
      `case when ${type} in (${types.map((item) => sqlString(item)).join(", ")}) then ${expression} end`,
    ];
  });

  const elsewhere = used.flatMap(([, types]) => types);

  return [
    [
      ctx.col("values", "valueText"),
      elsewhere.length === 0
        ? `${value} #>> '{}'`
        : `case when ${type} not in (${elsewhere.map((item) => sqlString(item)).join(", ")}) then ${value} #>> '{}' end`,
    ],
    ...own,
  ];
}

/** The managed values table of the keyed layout. */
function keyedTable(ctx: BlockSqlContext, options: KeyedOptions): string {
  const values = ctx.table("values");
  const c = (logical: string): string => ctx.col("values", logical);

  const optional = (logical: string, type: string): readonly string[] =>
    ctx.has("values", logical) ? [`${c(logical)} ${type}`] : [];

  const poly = polymorphic(ctx);

  const lines = [
    `${c("id")} uuid primary key default gen_random_uuid()`,
    `${c("tenant")} ${ctx.idType} not null`,
    ...(poly
      ? [`${c("subjectType")} text not null`, `${c("subjectId")} text not null`]
      : []),
    ...boundSubjects(ctx).map(
      (subject) => `${sqlIdent(subject.column)} ${subject.idType ?? "text"}`,
    ),
    `${c("key")} text not null`,
    `${c("label")} text not null`,
    `${c("type")} text not null check (${c("type")} in (${CUSTOM_FIELD_TYPES.map((type) => sqlString(type)).join(", ")}))`,
    `${c("valueText")} text`,
    `${c("valueNumber")} numeric`,
    `${c("valueDate")} date`,
    `${c("valueBool")} boolean`,
    ...optional("optionId", "uuid"),
    ...optional("valueJson", "jsonb"),
    ...optional("valueUrl", "text"),
    ...optional("valueEmail", "text"),
    ...optional(
      "rank",
      options.rankType === "integer" ? "integer" : 'text collate "C"',
    ),
    ...optional("createdAt", "timestamptz not null default now()"),
    ...optional("updatedAt", "timestamptz not null default now()"),
    ...(poly
      ? [
          `unique (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("key")})`,
        ]
      : []),
  ];

  return `create table if not exists ${values} (
  ${lines.join(",\n  ")}
);
${lockTable(values, { read: true })}
`;
}

/**
 * The keyed layout: each value row carries its field's key, label and type, and
 * its value in the column of that type. `set_field_value` upserts by subject
 * and key, `delete_field_value` removes one row.
 */
export function keyedFields(
  ctx: BlockSqlContext,
  keys: { readonly manage: string; readonly read: string },
  options: KeyedOptions,
): string {
  checkSubjectColumns(ctx, true);

  if (options.readAccess === "record" && !ctx.installed("subjects")) {
    throw new TypeError(
      'blocks.custom-fields.options.readAccess "record" checks can_subject; add the subjects block to blocks',
    );
  }

  for (const logical of ["key", "label", "type"]) {
    if (!ctx.has("values", logical)) {
      throw new TypeError(
        `blocks.custom-fields.columns.values.${logical} can't be null with layout "keyed"`,
      );
    }
  }

  const values = ctx.table("values");
  const c = (logical: string): string => ctx.col("values", logical);
  const fn = (name: string): string => ctx.fn(name);
  const subjects = fieldSubjects(ctx);
  const bound = boundSubjects(ctx);
  const poly = polymorphic(ctx);

  const check = (type: string, id: string, tenant: string): string =>
    andSubjectAction(
      subjectReadable(ctx, subjects, { type, id, tenant }),
      subjectActionCheck(ctx, subjects, { type, id }, ["fields"]),
    );

  const s = (name: string): string => `set_field_value.${name}`;
  const assignments = valueAssignments(ctx, "v_type", s("value"));
  const tableName = ctx.tableName("values");
  const qualified = `${sqlIdent(tableName.schema)}.${sqlIdent(tableName.name)}`;
  const integerRank = options.rankType === "integer";

  const rankValue = (value: string): string =>
    integerRank
      ? asColumnType(qualified, ctx.colName("values", "rank"), value)
      : value;

  const insertColumns = [
    c("tenant"),
    ...(poly ? [c("subjectType"), c("subjectId")] : []),
    ...bound.map((subject) => sqlIdent(subject.column)),
    c("key"),
    c("label"),
    c("type"),
    ...assignments.map(([column]) => column),
    ...(ctx.has("values", "rank") ? [c("rank")] : []),
  ];

  const insertValues = [
    s("tenant"),
    ...(poly
      ? [ctx.cast("values", "subjectType", s("subject_type")), s("subject_id")]
      : []),
    ...bound.map(
      (subject) =>
        `case when ${s("subject_type")} = ${sqlString(subject.type)} then ${asColumnType(qualified, subject.column, s("subject_id"))} end`,
    ),
    s("key"),
    s("label"),
    ctx.cast("values", "type", "v_type"),
    ...assignments.map(([, expression]) => expression),
    ...(ctx.has("values", "rank")
      ? [
          integerRank
            ? `coalesce(${rankValue(s("rank"))}, (select coalesce(max(v.${c("rank")}), 0) + 1 from ${values} v where v.${c("tenant")} = ${s("tenant")} and ${subjectMatch(ctx, "v", s("subject_type"), s("subject_id"))}))`
            : rankValue(s("rank")),
        ]
      : []),
  ];

  const updates = [
    `${c("label")} = ${s("label")}`,
    `${c("type")} = ${ctx.cast("values", "type", "v_type")}`,
    ...assignments.map(([column, expression]) => `${column} = ${expression}`),
    ...(ctx.has("values", "rank")
      ? [`${c("rank")} = coalesce(${rankValue(s("rank"))}, v.${c("rank")})`]
      : []),
    ...(ctx.has("values", "updatedAt") ? [`${c("updatedAt")} = now()`] : []),
  ];

  const order = ctx.has("values", "rank")
    ? `v.${c("rank")}${integerRank ? "" : ' collate "C"'} nulls last, v.${c("key")}`
    : `v.${c("key")}`;

  const byRecord = options.readAccess === "record";

  const readable = byRecord
    ? `(auth.role() = 'service_role' or (${subjectReadable(ctx, subjects, {
        type: "read_field_values.subject_type",
        id: "read_field_values.subject_id",
        tenant: "read_field_values.tenant",
      })}) and coalesce(${ctx.of("subjects").fn("can_subject")}(read_field_values.subject_type, read_field_values.subject_id, 'read'), false))`
    : `(auth.role() = 'service_role' or ${ctx.scope.can("read_field_values.tenant", keys.read)})`;

  const removed = rowSubject(ctx, "v");

  return `${ctx.owns("values") ? keyedTable(ctx, options) : ""}
drop function if exists ${fn("set_field_value")}(${ctx.idType}, text, text, uuid, text);

-- Sets one field of a subject by key: the value goes to the column of its
-- type and the other value columns are cleared. A key the subject already
-- has is updated, unless if_absent asks for FIELD_EXISTS instead.
create or replace function ${fn("set_field_value")}(tenant ${ctx.idType}, subject_type text, subject_id text, key text, label text, type text, value jsonb, rank text default null, if_absent boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_type text := ${s("type")};
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can(s("tenant"), keys.manage)}) then
    ${fail("FIELD_FORBIDDEN", "not allowed to set custom fields")}
  end if;
  if coalesce(trim(${s("key")}), '') = '' or coalesce(trim(${s("label")}), '') = '' or v_type is null or v_type not in (${CUSTOM_FIELD_TYPES.map((type) => sqlString(type)).join(", ")}) then
    ${fail("FIELD_INVALID", "a field needs a key, a label and a known type", "22023")}
  end if;
  if not (${customFieldValueCheck("v_type", `${s("value")} #>> '{}'`, ctx.schemaName)}) then
    ${fail("FIELD_VALUE_INVALID", "the value doesn't match the field's format", "22023")}
  end if;
  if not (${check(s("subject_type"), s("subject_id"), s("tenant"))}) then
    ${fail("FIELD_SUBJECT_FORBIDDEN", "not allowed to set fields on this record")}
  end if;
  select v.${c("id")} into v_id from ${values} v
  where v.${c("tenant")} = ${s("tenant")}
    and ${subjectMatch(ctx, "v", s("subject_type"), s("subject_id"))}
    and v.${c("key")} = ${s("key")}
  for update;
  if v_id is not null and ${s("if_absent")} then
    ${fail("FIELD_EXISTS", "the record already has this field", "23505")}
  end if;
  begin
    if v_id is null then
      insert into ${values} (${insertColumns.join(", ")})
      values (${insertValues.join(", ")})
      returning ${c("id")} into v_id;
    else
      update ${values} v set ${updates.join(", ")}
      where v.${c("id")} = v_id;
    end if;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    ${fail("FIELD_VALUE_INVALID", "the value doesn't fit the field's type", "22023")}
  end;
  ${ctx.record({
    type: "field_value.set",
    payload: `jsonb_build_object('organizationId', ${s("tenant")}, 'id', v_id, 'subjectType', ${s("subject_type")}, 'subjectId', ${s("subject_id")})`,
    subject: `'field-values/' || v_id::text`,
    tenant: s("tenant"),
    audit: false,
  })}
  return (select ${rowJson(ctx, "v", integerRank)} from ${values} v where v.${c("id")} = v_id);
end;
$$;
${userGrant(`${fn("set_field_value")}(${ctx.idType}, text, text, text, text, text, jsonb, text, boolean)`)}

-- Every field of a subject as typed rows, in rank order (then by key).
create or replace function ${fn("read_field_values")}(tenant ${ctx.idType}, subject_type text, subject_id text)
returns jsonb
language ${byRecord ? "plpgsql" : "sql"}
stable
security definer
set search_path = ''
as $$
${byRecord ? "begin\n  return (\n" : ""}  select coalesce(jsonb_agg(${rowJson(ctx, "v", integerRank)} order by ${order}), '[]'::jsonb)
  from ${values} v
  where v.${c("tenant")} = read_field_values.tenant
    and ${subjectMatch(ctx, "v", "read_field_values.subject_type", "read_field_values.subject_id")}
    and ${readable}${byRecord ? "\n  );\nend;" : ""}
$$;
${userGrant(`${fn("read_field_values")}(${ctx.idType}, text, text)`)}

-- Removes one field value.
create or replace function ${fn("delete_field_value")}(value_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_type text;
  v_subject text;
begin
  select v.${c("tenant")}, ${removed.type}, ${removed.id} into v_tenant, v_type, v_subject
  from ${values} v where v.${c("id")} = delete_field_value.value_id;
  if not found then
    ${fail("FIELD_VALUE_NOT_FOUND", "field value not found", "P0002")}
  end if;
  if not (auth.role() = 'service_role' or (${ctx.scope.can("v_tenant", keys.manage)} and ${check("v_type", "v_subject", "v_tenant")})) then
    ${fail("FIELD_FORBIDDEN", "not allowed to delete this field value")}
  end if;
  delete from ${values} where ${c("id")} = delete_field_value.value_id;
  ${ctx.record({
    type: "field_value.deleted",
    payload: `jsonb_build_object('organizationId', v_tenant, 'id', delete_field_value.value_id, 'subjectType', v_type, 'subjectId', v_subject)`,
    subject: `'field-values/' || delete_field_value.value_id::text`,
    tenant: "v_tenant",
    audit: false,
  })}
  return true;
end;
$$;
${userGrant(`${fn("delete_field_value")}(uuid)`)}
`;
}

/** The contract of the keyed layout. */
export function keyedContract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "read_field_values",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "set_field_value",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "text",
        "jsonb",
        "text",
        "boolean",
      ],
      returns: "jsonb",
    },
    { name: "delete_field_value", args: ["uuid"], returns: "boolean" },
  ];
}
