import type { BlockSqlLayout } from "./module-types.ts";

import { withoutComments } from "./audit-registrations.ts";
import {
  NAME,
  TABLE,
  closingParen,
  declaredTableColumns,
  qualified,
  splitTopLevel,
  unquote,
} from "./schema-scan.ts";

/** A foreign key the schema files declare. */
export interface DeclaredForeignKey {
  /** `schema.table`, unquoted. */
  readonly table: string;
  readonly columns: readonly string[];
  /** The referenced `schema.table`, unquoted. */
  readonly references: string;
  /**
   * The referenced columns. Without a column list, the referenced table's
   * declared primary key, or `id` when the files don't declare one.
   */
  readonly referencedColumns: readonly string[];
}

const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

const LIST = String.raw`\(\s*(${NAME}(?:\s*,\s*${NAME})*)\s*\)`;

const INLINE = /* @__PURE__ */ new RegExp(
  String.raw`\breferences\s+(${TABLE_NAME})(?:\s*\(\s*(${NAME})\s*\))?`,
  "i",
);

const CONSTRAINT = /* @__PURE__ */ new RegExp(
  String.raw`^(?:constraint\s+${NAME}\s+)?foreign\s+key\s*${LIST}\s*references\s+(${TABLE_NAME})(?:\s*${LIST})?`,
  "i",
);

const PRIMARY = /* @__PURE__ */ new RegExp(
  String.raw`^(?:constraint\s+${NAME}\s+)?primary\s+key\s*${LIST}`,
  "i",
);

const ALTER = /* @__PURE__ */ new RegExp(
  String.raw`\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${TABLE_NAME})\s+add\s+((?:constraint\s+${NAME}\s+)?foreign\s+key\s*${LIST}\s*references\s+${TABLE_NAME}(?:\s*${LIST})?)`,
  "gi",
);

const TABLE_CONSTRAINT =
  /^(constraint|check|unique|primary|foreign|exclude|like)\b/i;

const names = (list: string | undefined): string[] =>
  list === undefined
    ? []
    : (list.match(new RegExp(NAME, "g")) ?? []).map(unquote);

interface Pending {
  readonly table: string;
  readonly columns: readonly string[];
  readonly references: string;
  readonly referencedColumns: readonly string[];
}

function constraintOf(table: string, text: string): Pending | undefined {
  const match = CONSTRAINT.exec(text);

  if (match === null) {
    return undefined;
  }

  return {
    table,
    columns: names(match[1]),
    references: qualified(match[2]!),
    referencedColumns: names(match[3]),
  };
}

/**
 * The foreign keys in `files`: `references` on a column, `foreign key` table
 * constraints and `alter table ... add constraint ... foreign key`, in the
 * order they appear. Only tables in `schemas` are kept.
 */
function declaredForeignKeys(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): DeclaredForeignKey[] {
  const pending: Pending[] = [];
  const primaryKeys = new Map<string, readonly string[]>();

  const inSchemas = (table: string): boolean =>
    schemas.includes(table.slice(0, table.indexOf(".")));

  for (const file of files) {
    const text = withoutComments(file.text);
    const found: { readonly index: number; readonly key: Pending }[] = [];

    for (const match of text.matchAll(TABLE)) {
      const table = qualified(match[1]!);
      const open = match.index + match[0].length - 1;
      const close = closingParen(text, open);

      if (close === -1) {
        continue;
      }

      for (const part of splitTopLevel(text.slice(open + 1, close))) {
        const primary = PRIMARY.exec(part);

        if (primary !== null) {
          primaryKeys.set(table, names(primary[1]));
          continue;
        }

        if (TABLE_CONSTRAINT.test(part)) {
          const key = constraintOf(table, part);

          if (key !== undefined) {
            found.push({ index: match.index, key });
          }

          continue;
        }

        const column = new RegExp(NAME).exec(part)?.[0];

        if (column === undefined) {
          continue;
        }

        if (/\bprimary\s+key\b/i.test(part)) {
          primaryKeys.set(table, [unquote(column)]);
        }

        const inline = INLINE.exec(part);

        if (inline !== null) {
          found.push({
            index: match.index,
            key: {
              table,
              columns: [unquote(column)],
              references: qualified(inline[1]!),
              referencedColumns: names(inline[2]),
            },
          });
        }
      }
    }

    for (const match of text.matchAll(ALTER)) {
      const key = constraintOf(qualified(match[1]!), match[2]!);

      if (key !== undefined) {
        found.push({ index: match.index, key });
      }
    }

    pending.push(
      ...found.toSorted((a, b) => a.index - b.index).map(({ key }) => key),
    );
  }

  return pending
    .filter((key) => inSchemas(key.table))
    .map((key) => ({
      ...key,
      referencedColumns:
        key.referencedColumns.length > 0
          ? key.referencedColumns
          : (primaryKeys.get(key.references) ?? ["id"]),
    }));
}

const APP_TRIGGER = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+(${NAME})\s+(?:before|after|instead\s+of)\s[^;]*?\bon\s+(${TABLE_NAME})[^;]*?\bexecute\s+(?:function|procedure)\s+(${TABLE_NAME})\s*\(`,
  "gi",
);

const FUNCTION_BODY = /* @__PURE__ */ new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?function\s+(${TABLE_NAME})\s*\([\s\S]*?\bas\s+(\$\w*\$)([\s\S]*?)\2`,
  "gi",
);

const ROW_COLUMN = /\b(?:new|old)\s*\.\s*"?([a-z_][\w$]*)"?/gi;

/**
 * The function body of each app trigger, by `schema.table`. Triggers named
 * `bsb_*` are the blocks' own and don't count, so a check the app already makes
 * is never emitted twice.
 */
export function appTriggerBodies(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): Readonly<Record<string, readonly string[]>> {
  const texts = files.map((file) => withoutComments(file.text));
  const bodies = new Map<string, string>();

  for (const text of texts) {
    for (const match of text.matchAll(FUNCTION_BODY)) {
      bodies.set(qualified(match[1]!), match[3]!);
    }
  }

  const found = new Map<string, string[]>();

  for (const text of texts) {
    for (const match of text.matchAll(APP_TRIGGER)) {
      const table = qualified(match[2]!);

      if (
        unquote(match[1]!).startsWith("bsb_") ||
        !schemas.includes(table.slice(0, table.indexOf(".")))
      ) {
        continue;
      }

      found.set(table, [
        ...(found.get(table) ?? []),
        bodies.get(qualified(match[3]!)) ?? "",
      ]);
    }
  }

  return Object.fromEntries(found);
}

/**
 * The columns each app trigger reads or writes through `new.<column>` or
 * `old.<column>`, by `schema.table`.
 */
function appTriggerColumns(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): Readonly<Record<string, readonly string[]>> {
  return Object.fromEntries(
    Object.entries(appTriggerBodies(files, schemas)).map(([table, bodies]) => {
      const columns = new Set<string>();

      for (const body of bodies) {
        for (const column of body.matchAll(ROW_COLUMN)) {
          columns.add(column[1]!.toLowerCase());
        }
      }

      return [table, [...columns]];
    }),
  );
}

/**
 * The layout fields `blocks.memberships.options.sameTenant.auto` derives its
 * entries from.
 */
export function sameTenantLayout(
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
): Required<
  Pick<BlockSqlLayout, "foreignKeys" | "declaredColumns" | "appTriggerColumns">
> {
  return {
    foreignKeys: declaredForeignKeys(files, schemas),
    appTriggerColumns: appTriggerColumns(files, schemas),
    declaredColumns: Object.fromEntries(
      [...declaredTableColumns(files, schemas)].map(([table, columns]) => [
        table,
        [...columns],
      ]),
    ),
  };
}
