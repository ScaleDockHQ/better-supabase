import { parseBsbComment } from "../sql/bsb-tags.ts";
import { sameTenantTag } from "../sql/table-facts.ts";
import { factsOf } from "./schema-reader/index.ts";

/** A column comment that carries `@bsb` tags. */
export interface ColumnTagComment {
  readonly schema: string;
  readonly name: string;
  readonly column: string;
  readonly comment: string;
}

/**
 * The `@bsb` column comments of a file, with an unqualified table in `public`.
 * The file is read first with `primeSchemaFacts`.
 */
export function columnTagComments(sql: string): ColumnTagComment[] {
  return factsOf(sql).comments.flatMap((comment) => {
    if (comment.target !== "column") {
      return [];
    }

    const parts = comment.name.split(".");
    const column = parts.at(-1);
    const name = parts.at(-2);
    const schema = parts.at(-3) ?? "public";

    return column !== undefined &&
      name !== undefined &&
      parseBsbComment(comment.text).tags.length > 0
      ? [{ schema, name, column, comment: comment.text }]
      : [];
  });
}

/** The `same-tenant` column tags, as `sameTenant` entries and skipped columns. */
export interface SameTenantTags {
  readonly entries: readonly Record<string, unknown>[];
  /** `schema.table.column` of each column tagged `same-tenant=false`. */
  readonly skip: readonly string[];
}

/**
 * Reads the `same-tenant` tags of the column comments in `texts`. A tagged
 * column with no foreign key is left out, and BS703 reports it. An entry
 * carries `shared` only when the tag sets it; the block otherwise follows the
 * nullability of the referenced tenant column.
 */
export function sameTenantTagsOf(
  texts: readonly string[],
  schemas: readonly string[],
  foreignKeys: readonly {
    readonly table: string;
    readonly columns: readonly string[];
    readonly references: string;
    readonly referencedColumns: readonly string[];
    readonly deferrable?: boolean;
  }[],
): SameTenantTags {
  const entries: Record<string, unknown>[] = [];
  const skip: string[] = [];

  for (const text of texts) {
    for (const found of columnTagComments(text)) {
      const fact = sameTenantTag(found.comment);

      if (fact === undefined || !schemas.includes(found.schema)) {
        continue;
      }

      const table = `${found.schema}.${found.name}`;

      if (fact.skip === true) {
        skip.push(`${table}.${found.column}`);
        continue;
      }

      // A single-column key on the column wins; otherwise a composite key that
      // holds it, whose other columns become `match` pairs.
      const key =
        foreignKeys.find(
          (candidate) =>
            candidate.table === table &&
            candidate.columns.length === 1 &&
            candidate.columns[0] === found.column,
        ) ??
        foreignKeys.find(
          (candidate) =>
            candidate.table === table &&
            candidate.columns.includes(found.column),
        );

      const at = key?.columns.indexOf(found.column) ?? -1;
      const referenced = key?.referencedColumns[at];

      if (key === undefined || referenced === undefined) {
        continue;
      }

      const companions = Object.fromEntries(
        key.columns.flatMap((column, index) => {
          const other = key.referencedColumns[index];

          return index === at || other === undefined ? [] : [[column, other]];
        }),
      );

      const match = { ...companions, ...fact.match };

      entries.push({
        table,
        column: found.column,
        ...(fact.tenant === undefined ? {} : { tenant: fact.tenant }),
        references: {
          table: key.references,
          column: referenced,
          ...(fact.where === undefined ? {} : { where: fact.where }),
          ...(fact.parentTenant === undefined
            ? {}
            : { tenant: fact.parentTenant }),
        },
        ...(Object.keys(match).length === 0 ? {} : { match }),
        ...(fact.through === undefined ? {} : { through: fact.through }),
        ...(key.deferrable === true ? { deferrable: true } : {}),
        ...(fact.shared === undefined ? {} : { shared: fact.shared }),
      });
    }
  }

  return { entries, skip };
}
