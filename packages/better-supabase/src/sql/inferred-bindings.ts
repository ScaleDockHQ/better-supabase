import type { BlockSqlContext } from "./context.ts";
import type { Subject } from "./subjects.ts";

import { sqlString } from "../core/template.ts";

const qualify = (table: string): string =>
  table.includes(".") ? table : `public.${table}`;

const unquoted = (table: string): string => table.replaceAll('"', "");

/** The single-column foreign keys from `from` into `to`, as `[column, key]`. */
function keysBetween(
  ctx: BlockSqlContext,
  from: string,
  to: string,
): readonly string[] {
  return ctx.foreignKeys.flatMap((key) =>
    key.table === from && key.references === to && key.columns.length === 1
      ? [key.columns[0] ?? ""]
      : [],
  );
}

/**
 * The column of `table` that references the record type's table, from the
 * foreign keys the schema files declare. `undefined` when there is none, an
 * error that lists the candidates when there are several.
 */
export function inferredColumn(
  ctx: BlockSqlContext,
  table: string,
  subject: Subject,
  where: string,
): string | undefined {
  const columns = keysBetween(
    ctx,
    qualify(unquoted(table)),
    qualify(subject.table),
  );

  if (columns.length > 1) {
    throw new TypeError(
      `${where}.column: ${table} has several foreign keys into ${subject.table} (${columns.join(", ")}). Name the one to use`,
    );
  }

  return columns[0];
}

export interface InferredLink {
  readonly table: string;
  readonly subject: string;
  readonly tag: string;
}

/**
 * The link table between the record type's table and the tags table: the one
 * table with a foreign key into each. `undefined` when there is none.
 */
export function inferredLink(
  ctx: BlockSqlContext,
  subject: Subject,
  tags: string,
  where: string,
): InferredLink | undefined {
  const subjectTable = qualify(subject.table);
  const tagsTable = qualify(unquoted(tags));

  const found = new Map<string, InferredLink>();

  for (const key of ctx.foreignKeys) {
    if (
      key.references !== subjectTable ||
      key.columns.length !== 1 ||
      key.table === subjectTable ||
      key.table === tagsTable
    ) {
      continue;
    }

    const tagKeys = keysBetween(ctx, key.table, tagsTable);

    if (tagKeys.length === 1) {
      found.set(key.table, {
        table: key.table,
        subject: key.columns[0] ?? "",
        tag: tagKeys[0] ?? "",
      });
    }
  }

  if (found.size > 1) {
    throw new TypeError(
      `${where}.links: several tables link ${subject.table} to ${tags} (${[...found.keys()].map((name) => sqlString(name)).join(", ")}). Name the one to use`,
    );
  }

  return [...found.values()][0];
}
