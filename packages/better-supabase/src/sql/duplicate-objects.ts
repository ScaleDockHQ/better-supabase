import { withoutComments } from "./audit-registrations.ts";
import {
  indexStatements,
  qualified,
  TRACK_UPDATED_AT_CALL,
} from "./schema-scan.ts";

/** A block object an app object of the same table already covers. */
export interface DuplicateObject {
  readonly kind: "index" | "trigger";
  /** `schema.table`. */
  readonly table: string;
  /** The block's index or trigger. */
  readonly block: string;
  /** The app's index, or the app's call that creates the trigger. */
  readonly app: string;
  /**
   * `identical` for the same keys, `weaker` for a unique key the app's narrower
   * one implies.
   */
  readonly reason: "identical" | "weaker" | "same-work";
}

const TRIGGER_CALL =
  /\bcreate\s+(?:or\s+replace\s+)?trigger\s+("?[\w$]+"?)\s+(?:before|after)\s[^;]*?\bon\s+((?:"?[\w$]+"?\s*\.\s*)?"?[\w$]+"?)[^;]*?\bexecute\s+(?:function|procedure)\s+([\w$."]+)\s*\(/gi;

const sameSet = (a: readonly string[], b: readonly string[]): boolean =>
  a.length === b.length && a.every((column) => b.includes(column));

/**
 * The indexes and triggers a block's files create on a table where the app's
 * files already make the same, or a stricter, guarantee: a unique index whose
 * columns are the same as, or a subset of, the block's unique key, and an
 * `updated_at` trigger the app creates with `track_updated_at()` next to a
 * block trigger that sets it. Both run on every write, or index every row, for
 * nothing.
 */
export function duplicateObjects(
  blockFiles: readonly { readonly contents: string }[],
  appFiles: readonly { readonly text: string }[],
  schemas: readonly string[],
): readonly DuplicateObject[] {
  const inSchemas = (table: string): boolean =>
    schemas.includes(table.slice(0, table.indexOf(".")));

  const app = appFiles.map((file) => withoutComments(file.text));
  const block = blockFiles.map((file) => withoutComments(file.contents));
  const found: DuplicateObject[] = [];

  const appIndexes = app
    .flatMap((text) => indexStatements(text))
    .filter(
      (index) =>
        index.unique &&
        !index.partial &&
        index.method === "btree" &&
        index.plain,
    );

  for (const index of block.flatMap((text) => indexStatements(text))) {
    if (
      !index.unique ||
      index.partial ||
      index.method !== "btree" ||
      !index.plain ||
      !inSchemas(index.table)
    ) {
      continue;
    }

    const covering = appIndexes.find(
      (other) =>
        other.table === index.table &&
        other.columns.every((column) => index.columns.includes(column)),
    );

    if (covering !== undefined) {
      found.push({
        kind: "index",
        table: index.table,
        block: index.name ?? index.columns.join(", "),
        app: covering.name ?? covering.columns.join(", "),
        reason: sameSet(covering.columns, index.columns)
          ? "identical"
          : "weaker",
      });
    }
  }

  const tracked = new Set(
    app.flatMap((text) =>
      [...text.matchAll(TRACK_UPDATED_AT_CALL)].map((match) =>
        qualified(match[1]!.includes(".") ? match[1]! : `public.${match[1]!}`),
      ),
    ),
  );

  for (const text of block) {
    for (const match of text.matchAll(TRIGGER_CALL)) {
      const table = qualified(match[2]!);
      const trigger = match[1]!.replaceAll('"', "");

      if (
        tracked.has(table) &&
        inSchemas(table) &&
        /updated_at/i.test(match[3]!) &&
        trigger !== "bsb_updated_at"
      ) {
        found.push({
          kind: "trigger",
          table,
          block: trigger,
          app: `track_updated_at('${table}')`,
          reason: "same-work",
        });
      }
    }
  }

  return found;
}
