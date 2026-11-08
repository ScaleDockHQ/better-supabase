import { withoutComments } from "./audit-registrations.ts";
import {
  NAME,
  declaredTableColumns,
  qualified,
  splitTopLevel,
  unquote,
} from "./schema-scan.ts";

/** A column a block adds to a table the app owns, with its statement. */
export interface OwnedColumn {
  /** `schema.table`, unquoted. */
  readonly table: string;
  readonly column: string;
  /** The block's `alter table ... add column if not exists ...;` statement. */
  readonly statement: string;
}

const TABLE_NAME = String.raw`${NAME}(?:\s*\.\s*${NAME})?`;

const ADD_COLUMN = /* @__PURE__ */ new RegExp(
  String.raw`\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${TABLE_NAME})\s+add\s+column\s+if\s+not\s+exists\s+(${NAME})[^;]*;`,
  "gi",
);

const APP_ADD_COLUMN = /* @__PURE__ */ new RegExp(
  String.raw`\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?(${TABLE_NAME})\s+(add\s+column\b[^;]*);`,
  "gi",
);

/** The columns the app's own files add with `alter table ... add column`. */
function addedByApp(
  files: readonly { readonly text: string }[],
): ReadonlyMap<string, ReadonlySet<string>> {
  const found = new Map<string, Set<string>>();

  for (const file of files) {
    for (const match of withoutComments(file.text).matchAll(APP_ADD_COLUMN)) {
      const table = qualified(match[1]!);
      const set = found.get(table) ?? new Set<string>();

      for (const part of splitTopLevel(match[2]!)) {
        const column = new RegExp(
          String.raw`^add\s+column\s+(?:if\s+not\s+exists\s+)?(${NAME})`,
          "i",
        ).exec(part.trim())?.[1];

        if (column !== undefined) {
          set.add(unquote(column));
        }
      }

      found.set(table, set);
    }
  }

  return found;
}

/**
 * The columns the rendered block files add with `add column if not exists` to a
 * table the app's own files create, when those files declare no such column.
 * Today the block adds them to the app's table; a later release leaves them
 * out, which turns the feature off, so the app's files should declare them (ADR
 * 0325).
 */
export function ownedColumns(
  rendered: readonly { readonly contents: string }[],
  appFiles: readonly { readonly text: string }[],
  schemas: readonly string[],
): readonly OwnedColumn[] {
  const declared = declaredTableColumns(appFiles, schemas);
  const added = addedByApp(appFiles);
  const seen = new Set<string>();
  const found: OwnedColumn[] = [];

  for (const file of rendered) {
    for (const match of withoutComments(file.contents).matchAll(ADD_COLUMN)) {
      const table = qualified(match[1]!);
      const column = unquote(match[2]!);
      const key = `${table}.${column}`;

      if (
        !declared.has(table) ||
        declared.get(table)!.has(column) ||
        added.get(table)?.has(column) === true ||
        seen.has(key)
      ) {
        continue;
      }

      seen.add(key);
      found.push({ table, column, statement: match[0].trim() });
    }
  }

  return found;
}
