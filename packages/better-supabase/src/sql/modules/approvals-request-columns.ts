import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

const WHERE = "blocks.approvals.options.requestColumns";

const SUBJECT_TYPE = /^[a-z][a-z0-9_]{0,62}$/u;

/**
 * `options.requestColumns`, checked: per subject type, the SQL expression of
 * each app column `open_approval` fills.
 */
function requestColumnsOf(
  ctx: BlockSqlContext,
  extras: readonly { readonly name: string }[],
): ReadonlyMap<string, ReadonlyMap<string, string>> {
  const raw: unknown = ctx.option("requestColumns");
  const result = new Map<string, ReadonlyMap<string, string>>();

  if (raw === undefined) {
    return result;
  }

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      `${WHERE} must map a subject type to { column: "SQL expression" }`,
    );
  }

  const types: Readonly<Record<string, unknown>> = { ...raw };

  for (const [type, columns] of Object.entries(types)) {
    if (!SUBJECT_TYPE.test(type)) {
      throw new TypeError(
        `${WHERE}: "${type}" is not a snake_case subject type`,
      );
    }

    if (
      typeof columns !== "object" ||
      columns === null ||
      Array.isArray(columns) ||
      Object.keys(columns).length === 0
    ) {
      throw new TypeError(
        `${WHERE}.${type} must map at least one column to a SQL expression`,
      );
    }

    const named: Readonly<Record<string, unknown>> = { ...columns };
    const values = new Map<string, string>();

    for (const [name, value] of Object.entries(named)) {
      if (!extras.some((each) => each.name === name)) {
        throw new TypeError(
          `${WHERE}.${type}.${name}: not a column the app adds to ${ctx.table("requests")}`,
        );
      }

      if (
        typeof value !== "string" ||
        value.trim() === "" ||
        value.includes(";")
      ) {
        throw new TypeError(
          `${WHERE}.${type}.${name} must be one SQL expression`,
        );
      }

      values.set(name, value);
    }

    result.set(type, values);
  }

  return result;
}

/**
 * The statements in `open_approval` that fill the app's own columns of the
 * request it just inserted, `v_req`.
 */
export function requestColumnsSql(
  ctx: BlockSqlContext,
  extras: readonly { readonly name: string; readonly ident: string }[],
): string {
  const c = (column: string): string => ctx.col("requests", column);

  return [...requestColumnsOf(ctx, extras)]
    .map(([type, columns]) => {
      const sets = [...columns].map(
        ([name, value]) =>
          `${extras.find((each) => each.name === name)?.ident ?? ""} = (${value})`,
      );

      return `
  if open_approval.subject_type = ${sqlString(type)} then
    update ${ctx.table("requests")} x set ${sets.join(", ")}
      from (select open_approval.tenant, open_approval.subject_id, open_approval.action, coalesce(open_approval.payload, '{}'::jsonb), v_requester) as subject (tenant, subject_id, action, payload, requested_by)
      where x.${c("id")} = v_req.${c("id")}
      returning x.* into v_req;
  end if;`;
    })
    .join("");
}

/**
 * `fields` without the columns `requestColumns` fills for the request's subject
 * type, so a caller can't overwrite them.
 */
export function fieldsWithoutRequestColumns(
  ctx: BlockSqlContext,
  extras: readonly { readonly name: string }[],
  fields: string,
  type: string,
): string {
  const whens = [...requestColumnsOf(ctx, extras)].map(
    ([subject, columns]) =>
      ` when ${sqlString(subject)} then ${fields} - array[${[...columns.keys()].map((name) => sqlString(name)).join(", ")}]::text[]`,
  );

  return whens.length === 0
    ? fields
    : `(case ${type}${whens.join("")} else ${fields} end)`;
}
