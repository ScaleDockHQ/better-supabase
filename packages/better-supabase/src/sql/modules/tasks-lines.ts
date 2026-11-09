import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { TaskNames } from "./tasks-functions.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { RANK_KEY_PATTERN, rankAfter } from "../rank-sql.ts";
import { fail, userGrant } from "../shared.ts";
import { lockModuleTable } from "./over-app.ts";

/**
 * Ordered specification lines and material lines on a work item, plus the
 * optional `estimated_minutes` column the items table maps like its estimate.
 */
export function taskLinesSql(ctx: BlockSqlContext, n: TaskNames): string {
  if (!ctx.manages) {
    return "";
  }

  const { fn, t, c } = n;
  const w = (column: string): string => c("items", column);
  const spec = ctx.hasTable("specification");
  const materials = ctx.hasTable("materials");

  if (!spec && !materials) {
    return "";
  }

  const editable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${w("tenant")}`, n.write)})`;

  const readable = (alias: string): string =>
    `(${n.service} or ${ctx.scope.can(`${alias}.${w("tenant")}`, n.read)})`;

  const missing = fail("TASK_NOT_FOUND", "work item not found", "P0002");

  const table = (
    logical: "specification" | "materials",
    body: string,
  ): string => {
    if (!ctx.hasTable(logical)) {
      return "";
    }

    const name = ctx.tableName(logical).name;
    const k = (column: string): string => c(logical, column);

    return `
create table if not exists ${t(logical)} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("item")} uuid not null references ${t("items")} (${w("id")}) on delete cascade,
  ${body}
  ${k("rank")} text collate "C" not null check (${k("rank")} ~ ${RANK_KEY_PATTERN}),
  ${k("createdAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`bsb_${name}_item_idx`)} on ${t(logical)} (${k("item")}, ${k("rank")});
${lockModuleTable(ctx, logical, { read: true })}
${renderPolicy(
  makePolicy({
    table: t(logical),
    name: sqlIdent(`bsb_${name}_read`),
    command: "select",
    roles: ["authenticated"],
    using: ctx.scope.check(k("tenant"), n.read),
  }),
  { target: t(logical) },
)}
`;
  };

  const variant = (): string => {
    if (!ctx.has("materials", "variant")) {
      return "";
    }

    const column = c("materials", "variant");

    const catalog =
      ctx.installed("catalog") && ctx.of("catalog").mode !== "custom"
        ? ctx.of("catalog")
        : undefined;

    const reference =
      catalog?.hasTable("variants") === true
        ? ` references ${catalog.table("variants")} (${catalog.col("variants", "id")}) on delete set null`
        : "";

    return `${column} uuid${reference},\n  `;
  };

  const specification = spec
    ? table(
        "specification",
        `${c("specification", "description")} text not null check (char_length(${c("specification", "description")}) between 1 and 500),
  ${c("specification", "quantity")} numeric(12, 3) check (${c("specification", "quantity")} >= 0),
  ${c("specification", "unit")} text check (char_length(${c("specification", "unit")}) between 1 and 30),
  ${c("specification", "estimate")} numeric(10, 2) check (${c("specification", "estimate")} >= 0),`,
      )
    : "";

  const material = materials
    ? table(
        "materials",
        `${variant()}${c("materials", "quantity")} numeric(12, 3) not null check (${c("materials", "quantity")} >= 0),
  ${c("materials", "unit")} text check (char_length(${c("materials", "unit")}) between 1 and 30),`,
      )
    : "";

  const save = (
    logical: "specification" | "materials",
    functionName: string,
    lineName: string,
    columns: readonly string[],
    values: readonly string[],
    sets: readonly string[],
  ): string => {
    if (!ctx.hasTable(logical)) {
      return "";
    }

    const k = (column: string): string => c(logical, column);
    const listed = columns.map((column) => k(column)).join(", ");

    return `
-- Adds a ${logical} line (the line id null) or changes one. A new line
-- without a rank goes after the last one. Needs tasks.write.
create or replace function ${fn(functionName)}(task uuid, ${lineName} uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${t("items")};
  v_id uuid := ${functionName}.${lineName};
  v_last text;
  v_line ${t(logical)};
begin
  if jsonb_typeof(${functionName}.attrs) is distinct from 'object' then
    ${fail("TASK_LINE_INVALID", "input must be an object", "22023")}
  end if;
  select * into v_row from ${t("items")} x
  where x.${w("id")} = ${functionName}.task and ${editable("x")} and x.${w("archivedAt")} is null;
  if v_row.${w("id")} is null then
    ${missing}
  end if;
  if v_id is null then
    select max(y.${k("rank")}) into v_last from ${t(logical)} y where y.${k("item")} = v_row.${w("id")};
    insert into ${t(logical)} (${k("tenant")}, ${k("item")}, ${listed}, ${k("rank")})
    values (v_row.${w("tenant")}, v_row.${w("id")}, ${values.join(", ")}, coalesce(nullif(${functionName}.attrs ->> 'rank', ''), ${rankAfter("v_last")}))
    returning * into v_line;
  else
    update ${t(logical)} y set ${sets.join(", ")}
    where y.${k("id")} = v_id and y.${k("item")} = v_row.${w("id")}
    returning * into v_line;
    if v_line.${k("id")} is null then
      ${fail("TASK_LINE_INVALID", "no such line on this work item", "22023")}
    end if;
  end if;
  return jsonb_build_object('id', v_line.${k("id")}, 'taskId', v_line.${k("item")}, 'rank', v_line.${k("rank")});
end;
$$;
${userGrant(`${fn(functionName)}(uuid, uuid, jsonb)`)}
`;
  };

  const list = (
    logical: "specification" | "materials",
    functionName: string,
    object: string,
  ): string => {
    if (!ctx.hasTable(logical)) {
      return "";
    }

    const k = (column: string): string => c(logical, column);

    return `
-- The ${logical} lines of one work item, in rank order. Needs tasks.read.
create or replace function ${fn(functionName)}(task uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${object} order by y.${k("rank")}, y.${k("id")}), '[]'::jsonb)
  from ${t("items")} x
  join ${t(logical)} y on y.${k("item")} = x.${w("id")}
  where x.${w("id")} = ${functionName}.task and ${readable("x")}
$$;
${userGrant(`${fn(functionName)}(uuid)`)}
`;
  };

  const specObject = spec
    ? `jsonb_build_object('id', y.${c("specification", "id")}, 'taskId', y.${c("specification", "item")}, 'description', y.${c("specification", "description")}, 'quantity', y.${c("specification", "quantity")}, 'unit', y.${c("specification", "unit")}, 'estimate', y.${c("specification", "estimate")}, 'rank', y.${c("specification", "rank")})`
    : "";

  const materialObject = materials
    ? `jsonb_build_object('id', y.${c("materials", "id")}, 'taskId', y.${c("materials", "item")}, 'variantId', y.${c("materials", "variant")}, 'quantity', y.${c("materials", "quantity")}, 'unit', y.${c("materials", "unit")}, 'rank', y.${c("materials", "rank")})`
    : "";

  return `${specification}${material}
${
  spec
    ? save(
        "specification",
        "save_task_specification_line",
        "line_id",
        ["description", "quantity", "unit", "estimate"],
        [
          "nullif(btrim(save_task_specification_line.attrs ->> 'description'), '')",
          "nullif(save_task_specification_line.attrs ->> 'quantity', '')::numeric",
          "nullif(btrim(save_task_specification_line.attrs ->> 'unit'), '')",
          "nullif(save_task_specification_line.attrs ->> 'estimate', '')::numeric",
        ],
        [
          `${c("specification", "description")} = coalesce(nullif(btrim(save_task_specification_line.attrs ->> 'description'), ''), ${c("specification", "description")})`,
          `${c("specification", "quantity")} = coalesce(nullif(save_task_specification_line.attrs ->> 'quantity', '')::numeric, ${c("specification", "quantity")})`,
          `${c("specification", "unit")} = case when save_task_specification_line.attrs ? 'unit' then nullif(btrim(save_task_specification_line.attrs ->> 'unit'), '') else ${c("specification", "unit")} end`,
          `${c("specification", "estimate")} = case when save_task_specification_line.attrs ? 'estimate' then nullif(save_task_specification_line.attrs ->> 'estimate', '')::numeric else ${c("specification", "estimate")} end`,
          `${c("specification", "rank")} = coalesce(nullif(save_task_specification_line.attrs ->> 'rank', ''), ${c("specification", "rank")})`,
        ],
      )
    : ""
}
${spec ? list("specification", "list_task_specification", specObject) : ""}
${
  materials
    ? save(
        "materials",
        "save_task_material_line",
        "line_id",
        ["variant", "quantity", "unit"],
        [
          "nullif(save_task_material_line.attrs ->> 'variantId', '')::uuid",
          "nullif(save_task_material_line.attrs ->> 'quantity', '')::numeric",
          "nullif(btrim(save_task_material_line.attrs ->> 'unit'), '')",
        ],
        [
          `${c("materials", "variant")} = coalesce(nullif(save_task_material_line.attrs ->> 'variantId', '')::uuid, ${c("materials", "variant")})`,
          `${c("materials", "quantity")} = coalesce(nullif(save_task_material_line.attrs ->> 'quantity', '')::numeric, ${c("materials", "quantity")})`,
          `${c("materials", "unit")} = case when save_task_material_line.attrs ? 'unit' then nullif(btrim(save_task_material_line.attrs ->> 'unit'), '') else ${c("materials", "unit")} end`,
          `${c("materials", "rank")} = coalesce(nullif(save_task_material_line.attrs ->> 'rank', ''), ${c("materials", "rank")})`,
        ],
      )
    : ""
}
${materials ? list("materials", "list_task_materials", materialObject) : ""}`;
}

/** The contract entries for the specification and material line functions. */
export function taskLinesContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return [
    ...(ctx.hasTable("specification")
      ? [
          {
            name: "save_task_specification_line",
            args: ["uuid", "uuid", "jsonb"],
            returns: "jsonb",
          },
          { name: "list_task_specification", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
    ...(ctx.hasTable("materials")
      ? [
          {
            name: "save_task_material_line",
            args: ["uuid", "uuid", "jsonb"],
            returns: "jsonb",
          },
          { name: "list_task_materials", args: ["uuid"], returns: "jsonb" },
        ]
      : []),
  ];
}
